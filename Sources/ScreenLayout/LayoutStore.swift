import AppKit
import AppIntents
import CoreGraphics
import Foundation
import Observation
import SpaceBridge

@MainActor @Observable final class LayoutStore {
    static let shared = LayoutStore()
    var state = StoredState() { didSet { persist() } }
    var displays: [DisplayInfo] = []
    var displaySpaces: [DisplaySpaces] = []
    var events: [DebugEvent] = []
    var selectedDisplayID: String?
    var selectedLayoutID: UUID?
    var selectedSpaceID: UUID?
    var selectedWindowID: UUID?
    var status = "Ready"
    var accessibilityTrusted = WindowAccess.trusted
    var newModeName = ""
    var focusNames: [String] = []
    var focusCatalogError: String?
    var appToAdd = ""
    var loginItemTick = 0
    var snapHotkeyError: String?
    var snapOverlayActive = false
    private var debounce: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var lastFocusError: String?
    private struct ActiveDrawer {
        let windowID: UInt32
        let bundleID: String
        let displayID: String
        let edge: DrawerEdge
        let slot: Int
        var expandedRect: UnitRect
        var expanded = false
    }
    private var activeDrawers: [ActiveDrawer] = []
    private var drawerTask: Task<Void, Never>?
    private var activeDrawerLayoutID: UUID?
    private var loggedCornerRemaps: Set<String> = []
    private var loggedSlotClamps: Set<String> = []
    private let fileURL: URL
    private var didLoadState = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("ScreenLayout", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("layouts.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                state = try JSONDecoder().decode(StoredState.self, from: data)
                didLoadState = true
            } catch {
                preserveUnreadableFile(error)
            }
        } else {
            didLoadState = true
        }
        migrateLegacyAssignments()
        migrateLegacySpaces()
        migrateLegacyDrawers()
        migrateCornerDrawers()
        WindowAccess.diagnostics = { [weak self] message in
            MainActor.assumeIsolated { self?.log(message) }
        }
        refreshDisplays(reason: "Startup")
        refreshFocusNames()
        log("Accessibility trusted: \(accessibilityTrusted)")
        log("Space move operation available: \(SLCanMoveWindows())")
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let error = CGDisplayRegisterReconfigurationCallback(displayCallback, pointer)
        log(error == .success ? "Display callback registered" : "Display callback registration failed: \(error.rawValue)")
        updateFocusMonitoring()
    }

    deinit {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayCallback, pointer)
    }

    private func preserveUnreadableFile(_ error: Error) {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("layouts.corrupt-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backup)
            status = "Could not read saved layouts; copied to \(backup.lastPathComponent). Saving is disabled."
        } catch {
            status = "Could not read saved layouts and could not back them up. Saving is disabled."
        }
        log("\(status) (\(error.localizedDescription))")
    }

    var displaySet: String { displays.map(\.id).sorted().joined(separator: "+") }
    var currentMode: String { state.preferences.focusModesEnabled ? state.preferences.selectedMode : "Default" }
    var relevantLayouts: [SavedLayout] { state.layouts.filter { $0.displaySet == displaySet } }
    private var selectedLayoutIndex: Int? { state.layouts.firstIndex(where: { $0.id == selectedLayoutID }) }
    var selectedLayout: SavedLayout? { state.layouts.first { $0.id == selectedLayoutID } }
    var selectableFocusNames: [String] {
        let names = ["Default"] + focusNames + state.preferences.modes + [state.preferences.selectedMode]
        return names.reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }
    }
    private func assignmentKey(_ mode: String, _ displaySet: String) -> String { "\(mode)|\(displaySet)" }
    private var assignmentKey: String { assignmentKey(currentMode, displaySet) }
    var preferredLayoutID: UUID? { state.preferences.preferredLayouts[assignmentKey] }
    private var activeLayout: SavedLayout? { relevantLayouts.first { $0.id == preferredLayoutID } }
    private var layoutForEditor: SavedLayout? {
        activeLayout ?? relevantLayouts.max(by: { $0.savedAt < $1.savedAt })
    }

    private func migrateLegacyAssignments() {
        for layout in state.layouts.sorted(by: { $0.savedAt > $1.savedAt }) {
            let key = assignmentKey(layout.mode, layout.displaySet)
            if state.preferences.preferredLayouts[key] == nil {
                state.preferences.preferredLayouts[key] = layout.id
            }
        }
    }

    private static func defaultSlot(for displayID: String) -> SpaceSlot {
        SpaceSlot(displayID: displayID, name: "Desktop 1")
    }

    private func migrateLegacySpaces() {
        for layoutIndex in state.layouts.indices where state.layouts[layoutIndex].spaces == nil {
            let displayIDs = Array(Set(state.layouts[layoutIndex].windows.map(\.displayID))).sorted()
            let slots = displayIDs.map { Self.defaultSlot(for: $0) }
            state.layouts[layoutIndex].spaces = slots
            for windowIndex in state.layouts[layoutIndex].windows.indices {
                let displayID = state.layouts[layoutIndex].windows[windowIndex].displayID
                state.layouts[layoutIndex].windows[windowIndex].spaceID = slots.first(where: { $0.displayID == displayID })?.id
            }
        }
    }

    private func migrateLegacyDrawers() {
        for layoutIndex in state.layouts.indices {
            for windowIndex in state.layouts[layoutIndex].windows.indices {
                let placement = state.layouts[layoutIndex].windows[windowIndex]
                guard let edge = placement.drawer,
                      (edge == .left || edge == .right),
                      abs(placement.rect.width - 1.0 / 6.0) < 0.02,
                      placement.rect.height > 0.95 else { continue }
                state.layouts[layoutIndex].windows[windowIndex].rect =
                    UnitRect(x: edge == .left ? 0 : 0.5, y: 0, width: 0.5, height: 1)
            }
        }
    }

    // Corner drawers now default to off. A corner stays on where the monitor saved a size for it or a
    // layout window uses it. An explicit stored count, including 0, is never overwritten.
    private func migrateCornerDrawers() {
        var wanted: [String: Set<DrawerEdge>] = [:]
        for (displayID, sizes) in state.preferences.drawers {
            for key in sizes.keys {
                if let edge = DrawerEdge(rawValue: key), edge.isCorner { wanted[displayID, default: []].insert(edge) }
            }
        }
        for layout in state.layouts {
            for placement in layout.windows {
                if let edge = placement.drawer, edge.isCorner { wanted[placement.displayID, default: []].insert(edge) }
            }
        }
        for (displayID, corners) in wanted {
            for corner in corners where state.preferences.drawerCounts[displayID]?[corner.rawValue] == nil {
                state.preferences.drawerCounts[displayID, default: [:]][corner.rawValue] = 1
            }
        }
    }

    func spaces(for display: DisplayInfo) -> [SpaceSlot] {
        selectedLayout?.spaces?.filter { $0.displayID == display.id } ?? []
    }

    var selectedSpace: SpaceSlot? { selectedLayout?.spaces?.first { $0.id == selectedSpaceID } }
    var canRemoveSelectedSpace: Bool { removalPlan() != nil }

    private func removalPlan() -> (layoutIndex: Int, slots: [SpaceSlot], selected: SpaceSlot, destination: SpaceSlot)? {
        guard let layoutIndex = selectedLayoutIndex,
              let slots = state.layouts[layoutIndex].spaces,
              let selected = slots.first(where: { $0.id == selectedSpaceID }) else { return nil }
        let others = slots.filter { $0.displayID == selected.displayID && $0.id != selected.id }
        if selected.kind == .desktop && !others.contains(where: { $0.kind == .desktop }) { return nil }
        guard let destination = others.first(where: { $0.kind == .desktop }) ?? others.first else { return nil }
        return (layoutIndex, slots, selected, destination)
    }

    func ensureSelectedSpace() {
        guard let layoutIndex = selectedLayoutIndex,
              let displayID = selectedDisplayID else { selectedSpaceID = nil; return }
        if !(state.layouts[layoutIndex].spaces ?? []).contains(where: { $0.displayID == displayID }) {
            var slots = state.layouts[layoutIndex].spaces ?? []
            slots.append(Self.defaultSlot(for: displayID))
            state.layouts[layoutIndex].spaces = slots
        }
        let slots = state.layouts[layoutIndex].spaces ?? []
        if !slots.contains(where: { $0.id == selectedSpaceID && $0.displayID == displayID }) {
            selectedSpaceID = slots.first(where: { $0.displayID == displayID })?.id
        }
    }

    func addSpace(kind: SpaceKind) {
        if kind == .desktop { refreshSpaces() }
        guard let layoutIndex = selectedLayoutIndex,
              let displayID = selectedDisplayID else { return }
        var slots = state.layouts[layoutIndex].spaces ?? []
        let number = slots.filter { $0.displayID == displayID && $0.kind == kind }.count + 1
        let slot = SpaceSlot(displayID: displayID,
                             name: kind == .desktop ? "Desktop \(number)" : "Full Screen \(number)", kind: kind)
        slots.append(slot)
        state.layouts[layoutIndex].spaces = slots
        selectedSpaceID = slot.id
        ensureSelectedWindow()
    }

    func addDesktops(through number: Int, display: DisplayInfo) {
        guard let layout = selectedLayout else { return }
        let missing = number - requiredDesktopSpaces(for: layout, display: display)
        for _ in 0..<max(1, missing) { addSpace(kind: .desktop) }
    }

    func moveSelectedSpace(_ offset: Int) {
        guard let layoutIndex = selectedLayoutIndex,
              var slots = state.layouts[layoutIndex].spaces,
              let source = slots.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        let indices = slots.indices.filter { slots[$0].displayID == slots[source].displayID }
        guard let position = indices.firstIndex(of: source), indices.indices.contains(position + offset) else { return }
        slots.swapAt(source, indices[position + offset])
        state.layouts[layoutIndex].spaces = slots
    }

    func removeSelectedSpace() {
        guard let plan = removalPlan() else { return }
        let (layoutIndex, selected, destination) = (plan.layoutIndex, plan.selected, plan.destination)
        var slots = plan.slots
        for index in state.layouts[layoutIndex].windows.indices where state.layouts[layoutIndex].windows[index].spaceID == selected.id {
            state.layouts[layoutIndex].windows[index].spaceID = destination.id
        }
        slots.removeAll { $0.id == selected.id }
        state.layouts[layoutIndex].spaces = slots
        selectedSpaceID = destination.id
        ensureSelectedWindow()
    }

    func moveWindowToSpace(_ windowID: UUID, spaceID: UUID) {
        guard let layoutIndex = selectedLayoutIndex,
              let slot = state.layouts[layoutIndex].spaces?.first(where: { $0.id == spaceID }),
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == windowID }) else { return }
        state.layouts[layoutIndex].windows[windowIndex].spaceID = spaceID
        state.layouts[layoutIndex].windows[windowIndex].displayID = slot.displayID
        selectedSpaceID = spaceID
        selectedDisplayID = slot.displayID
        ensureSelectedWindow()
    }

    func log(_ message: String) {
        events.insert(DebugEvent(message: message), at: 0)
        if events.count > 500 { events.removeLast() }
    }

    func refreshAccessibility() {
        let trusted = WindowAccess.trusted
        if trusted != accessibilityTrusted { log("Accessibility trusted: \(trusted)") }
        accessibilityTrusted = trusted
    }

    func refreshLoginItem() { loginItemTick += 1 }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            log(LoginItem.statusText)
        } catch {
            status = "Could not \(on ? "enable" : "disable") launch at login: \(error.localizedDescription)"
            log(status)
        }
        refreshLoginItem()
    }

    func refreshFocusNames() {
        let result = FocusCatalog.load()
        focusNames = result.names
        focusCatalogError = result.error
        log(result.error ?? "Loaded \(focusNames.count) macOS Focus names")
    }

    func displayEvent(id: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        log("Display \(id): \(flagDescription(flags))")
        guard !flags.contains(.beginConfigurationFlag) else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.refreshDisplays(reason: "Display configuration changed")
            if self?.state.preferences.autoRestoreOnDisplayChange == true {
                self?.log("Automatic restore: display configuration changed")
                self?.restoreLatest()
            }
        }
    }

    private func flagDescription(_ flags: CGDisplayChangeSummaryFlags) -> String {
        var parts: [String] = []
        if flags.contains(.beginConfigurationFlag) { parts.append("begin") }
        if flags.contains(.addFlag) { parts.append("plugged in") }
        if flags.contains(.removeFlag) { parts.append("unplugged") }
        if flags.contains(.movedFlag) { parts.append("moved") }
        if flags.contains(.setMainFlag) { parts.append("main changed") }
        if flags.contains(.setModeFlag) { parts.append("mode changed") }
        return parts.isEmpty ? "configuration updated" : parts.joined(separator: ", ")
    }

    func refreshDisplays(reason: String = "Manual refresh") {
        refreshAccessibility()
        let previous = Set(displays.map(\.id))
        displays = DisplayInfo.current()
        refreshSpaces()
        for display in displays where state.preferences.grids[display.id] == nil {
            state.preferences.grids[display.id] = .smart(for: display)
        }
        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id
        }
        selectedLayoutID = layoutForEditor?.id
        ensureSelectedSpace()
        ensureSelectedWindow()
        let names = displays.map { "\($0.name) [\($0.id.prefix(8))]" }.joined(separator: ", ")
        log("\(reason): \(displays.count) display(s): \(names)")
        if !previous.isEmpty && previous != Set(displays.map(\.id)) { status = "Display set changed" }
    }

    func refreshSpaces() {
        if let snapshots = SpaceInventory.current() {
            if snapshots != displaySpaces {
                displaySpaces = snapshots
                let counts = snapshots.map { "\($0.displayID.prefix(8)): \($0.desktopCount) desktop" }.joined(separator: ", ")
                log("Spaces: \(counts)")
            }
        } else {
            log("Space count unavailable on this macOS build")
        }
    }

    func desktopSpaceCount(for display: DisplayInfo) -> Int? {
        displaySpaces.first(where: { $0.displayID == display.id })?.desktopCount
    }

    func requiredDesktopSpaces(for layout: SavedLayout, display: DisplayInfo) -> Int {
        max(1, layout.spaces?.filter { $0.displayID == display.id && $0.kind == .desktop }.count ?? 1)
    }

    func drawerSize(for edge: DrawerEdge, display: DisplayInfo) -> DrawerSize {
        state.preferences.drawers[display.id]?[edge.rawValue] ?? .standard(for: edge)
    }

    func cornerRule(for display: DisplayInfo) -> CornerRule {
        state.preferences.cornerRules[display.id] ?? .separate
    }

    func cornerRule(forDisplayID id: String) -> CornerRule {
        state.preferences.cornerRules[id] ?? .separate
    }

    func setCornerRule(_ rule: CornerRule, for display: DisplayInfo) {
        state.preferences.cornerRules[display.id] = rule
        refreshRestingDrawers(display: display)
    }

    func setDrawerSize(_ size: DrawerSize, for edge: DrawerEdge, display: DisplayInfo) {
        var settings = state.preferences.drawers[display.id] ?? [:]
        settings[edge.rawValue] = DrawerSize(width: min(1, max(0.05, size.width)),
                                             height: min(1, max(0.05, size.height)))
        state.preferences.drawers[display.id] = settings
        refreshRestingDrawers(display: display)
    }

    func resetDrawerSize(for edge: DrawerEdge, display: DisplayInfo) {
        state.preferences.drawers[display.id]?.removeValue(forKey: edge.rawValue)
        refreshRestingDrawers(display: display)
    }

    // Requested drawers at a position: edges 0 to 8 (default 1), corners 0 or 1 (default off).
    func drawerCount(for edge: DrawerEdge, displayID: String) -> Int {
        let stored = state.preferences.drawerCounts[displayID]?[edge.rawValue] ?? DrawerGeometry.defaultCount(for: edge)
        return min(edge.isCorner ? 1 : DrawerGeometry.maxSlots, max(0, stored))
    }

    func drawerCount(for edge: DrawerEdge, display: DisplayInfo) -> Int {
        drawerCount(for: edge, displayID: display.id)
    }

    func setDrawerCount(_ count: Int, for edge: DrawerEdge, display: DisplayInfo) {
        var settings = state.preferences.drawerCounts[display.id] ?? [:]
        settings[edge.rawValue] = min(edge.isCorner ? 1 : DrawerGeometry.maxSlots, max(0, count))
        state.preferences.drawerCounts[display.id] = settings
        refreshRestingDrawers(display: display)
    }

    // A position is enabled when its count is above 0 and the display's corner rule allows it.
    func isDrawerEnabled(_ edge: DrawerEdge, displayID: String) -> Bool {
        edge.isLegal(for: cornerRule(forDisplayID: displayID)) && drawerCount(for: edge, displayID: displayID) > 0
    }

    // Slots a position really has: the requested count, capped by the grid cells along it when snapping.
    func effectiveDrawerCount(for edge: DrawerEdge, display: DisplayInfo) -> Int {
        drawerRects(for: display).keys.filter { $0.edge == edge }.count
    }

    // The enabled edge a saved assignment uses now: the rule's edge, else the nearest enabled edge
    // (around the screen, clockwise first on a tie), else nil so the window stays normal.
    func usableDrawerEdge(_ edge: DrawerEdge, displayID: String) -> DrawerEdge? {
        let resolved = edge.resolved(for: cornerRule(forDisplayID: displayID))
        if isDrawerEnabled(resolved, displayID: displayID) { return resolved }
        let ring = DrawerEdge.allCases
        guard let from = ring.firstIndex(of: resolved) else { return nil }
        func distance(_ other: DrawerEdge) -> (Int, Int) {
            let forward = ((ring.firstIndex(of: other) ?? 0) - from + ring.count) % ring.count
            return (min(forward, ring.count - forward), forward)
        }
        return ring.filter { !$0.isCorner && isDrawerEnabled($0, displayID: displayID) }
            .min { distance($0) < distance($1) }
    }

    // Resting rectangles for every legal drawer slot on a display, in `area` (default: the display's
    // visible frame). The single source for the editor preview, restore and live drawers.
    func drawerRects(for display: DisplayInfo, in area: CGRect? = nil, enabling extra: DrawerEdge? = nil) -> [DrawerKey: CGRect] {
        var configured: [DrawerEdge: DrawerSize] = [:]
        var counts: [DrawerEdge: Int] = [:]
        for (key, size) in state.preferences.drawers[display.id] ?? [:] {
            if let edge = DrawerEdge(rawValue: key) { configured[edge] = size }
        }
        for edge in DrawerEdge.allCases { counts[edge] = drawerCount(for: edge, display: display) }
        if let extra, counts[extra] == 0 { counts[extra] = 1 }
        let snap = grid(for: display).snapToGrid
        return DrawerGeometry.rects(in: area ?? display.visibleFrame, configured: configured, rule: cornerRule(for: display),
                                    counts: counts, grid: snap ? gridGeometry(for: display) : nil)
    }

    func isDrawerConfigured(_ edge: DrawerEdge, display: DisplayInfo) -> Bool {
        state.preferences.drawers[display.id]?[edge.rawValue] != nil
    }

    // The drawer a placement uses now, with the rule's edge and a clamped slot. No logging.
    func drawerKey(for placement: WindowPlacement) -> DrawerKey? {
        guard let edge = placement.drawer,
              let display = displays.first(where: { $0.id == placement.displayID }) else { return nil }
        guard let resolved = usableDrawerEdge(edge, displayID: display.id) else { return nil }
        let count = effectiveDrawerCount(for: resolved, display: display)
        guard count > 0 else { return nil }
        return DrawerKey(edge: resolved, slot: min(max(0, placement.drawerSlot), count - 1))
    }

    // Other windows in the layout that use the same drawer slot on a display.
    func drawerOccupants(of key: DrawerKey, displayID: String, excluding windowID: UUID, in layout: SavedLayout) -> [WindowPlacement] {
        layout.windows.filter { $0.id != windowID && $0.displayID == displayID && drawerKey(for: $0) == key }
    }

    // The drawer and resting frame a saved drawer assignment uses now. A corner assignment that is
    // illegal under the display's rule maps to the rule's edge, and a slot beyond the current count
    // maps to the last slot; the saved layout is not changed.
    private func restingTarget(for edge: DrawerEdge, slot: Int, display: DisplayInfo, placement: WindowPlacement? = nil) -> (key: DrawerKey, frame: CGRect)? {
        let rule = cornerRule(for: display)
        let ruleEdge = edge.resolved(for: rule)
        let usable = usableDrawerEdge(edge, displayID: display.id)
        if let placement {
            if ruleEdge != edge, usable == ruleEdge,
               loggedCornerRemaps.insert("\(placement.id)-\(rule.rawValue)").inserted {
                log("\(placement.appName): \(edge.title) drawer is unavailable with \(rule.title.lowercased()) corners; using \(ruleEdge.title.lowercased())")
            } else if usable != ruleEdge,
                      loggedCornerRemaps.insert("\(placement.id)-disabled-\(ruleEdge.rawValue)-\(usable?.rawValue ?? "none")").inserted {
                log("\(placement.appName): \(ruleEdge.title) drawer is disabled; \(usable.map { "using \($0.title.lowercased())" } ?? "staying normal")")
            }
        }
        guard let resolved = usable else { return nil }
        let rects = drawerRects(for: display)
        let count = rects.keys.filter { $0.edge == resolved }.count
        guard count > 0 else { return nil }
        let clamped = min(max(0, slot), count - 1)
        if clamped != slot, let placement,
           loggedSlotClamps.insert("\(placement.id)-\(resolved.rawValue)-\(count)").inserted {
            log("\(placement.appName): \(resolved.title) drawer slot \(slot + 1) is beyond the \(count) available; using slot \(clamped + 1)")
        }
        let key = DrawerKey(edge: resolved, slot: clamped)
        guard let frame = rects[key] else { return nil }
        return (key, frame)
    }

    private func refreshRestingDrawers(display: DisplayInfo) {
        for drawer in activeDrawers where drawer.displayID == display.id && !drawer.expanded {
            guard let target = restingTarget(for: drawer.edge, slot: drawer.slot, display: display) else { continue }
            _ = WindowAccess.setDrawerFrame(edge: target.key.edge, expanded: false, display: display,
                                            restingFrame: target.frame, expandedRect: drawer.expandedRect,
                                            windowID: drawer.windowID, bundleID: drawer.bundleID)
        }
    }

    func capture() {
        accessibilityTrusted = WindowAccess.trusted
        guard accessibilityTrusted else { WindowAccess.requestPermission(); status = "Accessibility is not trusted for this build"; log(status); return }
        var windows = WindowAccess.capture(displays: displays)
        let slots = displays.map { Self.defaultSlot(for: $0.id) }
        for index in windows.indices {
            windows[index].spaceID = slots.first(where: { $0.displayID == windows[index].displayID })?.id
        }
        let layout = SavedLayout(name: "Capture \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                                 displaySet: displaySet, mode: currentMode, windows: windows, spaces: slots)
        state.layouts.append(layout)
        state.preferences.preferredLayouts[assignmentKey] = layout.id
        selectedLayoutID = layout.id
        selectedSpaceID = slots.first(where: { $0.displayID == selectedDisplayID })?.id
        selectedWindowID = windows.first?.id
        status = "Captured \(windows.count) windows"
        log(status)
    }

    func createBlankLayout() {
        let slots = displays.map { Self.defaultSlot(for: $0.id) }
        let layout = SavedLayout(name: "New layout", displaySet: displaySet, mode: currentMode,
                                 windows: [], spaces: slots)
        state.layouts.append(layout)
        selectedLayoutID = layout.id
        selectedSpaceID = slots.first(where: { $0.displayID == selectedDisplayID })?.id
        selectedWindowID = nil
        status = "Created new layout"
        log(status)
    }

    func renameSelectedLayout(_ name: String) {
        guard let index = selectedLayoutIndex else { return }
        state.layouts[index].name = name
        state.layouts[index].savedAt = .now
    }

    func restoreLatest() {
        guard let layout = activeLayout else { log("No layout for current displays and mode"); return }
        restore(layout)
    }

    func restoreSelected() {
        guard let layout = selectedLayout else { return }
        restore(layout)
    }

    private func restore(_ layout: SavedLayout) {
        let slotsByDisplay = Dictionary(grouping: layout.spaces ?? [], by: \.displayID)
        if slotsByDisplay.values.contains(where: { $0.contains(where: { $0.kind == .fullScreen }) }) {
            status = "Full-screen Space slots cannot be applied yet"
            log(status)
            return
        }
        refreshSpaces()
        var targets: [UUID: UInt64] = [:]
        for display in displays {
            let required = requiredDesktopSpaces(for: layout, display: display)
            guard let inventory = displaySpaces.first(where: { $0.displayID == display.id }),
                  inventory.desktopCount >= required else {
                status = "Cannot restore ‘\(layout.name)’: \(display.name) needs \(required) desktop Spaces"
                log(status)
                return
            }
            let actual = inventory.spaces.filter(\.isDesktop)
            for (slot, space) in (slotsByDisplay[display.id] ?? []).enumerated() {
                guard slot < actual.count else { break }
                targets[space.id] = actual[slot].id
            }
        }
        accessibilityTrusted = WindowAccess.trusted
        guard accessibilityTrusted else { WindowAccess.requestPermission(); status = "Accessibility is not trusted for this build"; log(status); return }
        let restingPlacements = layout.windows.map { placement -> WindowPlacement in
            var resting = placement
            if let edge = placement.drawer,
               let display = displays.first(where: { $0.id == placement.displayID }),
               let target = restingTarget(for: edge, slot: placement.drawerSlot, display: display, placement: placement) {
                resting.rect = UnitRect(target.frame, in: display.visibleFrame)
            }
            return resting
        }
        let multiSpace = slotsByDisplay.values.contains { $0.count > 1 }
        if multiSpace && !SLCanMoveWindows() {
            status = "Moving windows between Spaces is unavailable on this macOS build"
            log(status)
            return
        }
        drawerTask?.cancel()
        drawerTask = nil
        activeDrawers = []
        activeDrawerLayoutID = nil
        if multiSpace {
            let result = WindowAccess.restoreAcrossSpaces(restingPlacements, displays: displays, targetSpaces: targets)
            status = "Restored \(result.moved) windows; skipped \(result.skipped); Space moves failed \(result.spaceFailed)"
        } else {
            let result = WindowAccess.restore(restingPlacements, displays: displays)
            status = "Restored \(result.moved) windows; skipped \(result.skipped)"
        }
        log("Restore ‘\(layout.name)’: \(status)")
        startDrawers(for: layout)
    }

    func setDrawerSlot(_ slot: Int, for windowID: UUID) {
        guard let layoutIndex = selectedLayoutIndex,
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == windowID }) else { return }
        state.layouts[layoutIndex].windows[windowIndex].drawerSlot = max(0, slot)
        state.layouts[layoutIndex].savedAt = .now
    }

    func setDrawer(_ edge: DrawerEdge?, for windowID: UUID) {
        guard let layoutIndex = selectedLayoutIndex,
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == windowID }) else { return }
        // The window keeps its existing rect: it becomes the drawer's active frame.
        state.layouts[layoutIndex].windows[windowIndex].drawer = edge
        state.layouts[layoutIndex].windows[windowIndex].drawerSlot = 0
        state.layouts[layoutIndex].savedAt = .now
    }

    private func startDrawers(for layout: SavedLayout) {
        var claimed: Set<UInt32> = []
        var slotOwners: [String: String] = [:]
        for placement in layout.windows {
            guard displays.contains(where: { $0.id == placement.displayID }) else { continue }
            let windowID = WindowAccess.windowID(for: placement, claimed: claimed)
            if windowID != 0 { claimed.insert(windowID) }
            guard let edge = placement.drawer else { continue }
            guard windowID != 0 else { log("Drawer window unavailable: \(placement.appName)"); continue }
            guard let display = displays.first(where: { $0.id == placement.displayID }),
                  let target = restingTarget(for: edge, slot: placement.drawerSlot, display: display, placement: placement),
                  WindowAccess.setDrawerFrame(edge: target.key.edge, expanded: false, display: display,
                                               restingFrame: target.frame,
                                               expandedRect: placement.rect,
                                               windowID: windowID, bundleID: placement.bundleID) else {
                log("Could not position drawer: \(placement.appName)")
                continue
            }
            let owner = "\(placement.displayID)-\(target.key.edge.rawValue)-\(target.key.slot)"
            if let other = slotOwners[owner] {
                log("\(placement.appName) shares the \(target.key.edge.title.lowercased()) drawer slot \(target.key.slot + 1) with \(other); the focused one expands and the other stays collapsed")
            }
            slotOwners[owner] = placement.appName
            activeDrawers.append(ActiveDrawer(windowID: windowID, bundleID: placement.bundleID,
                                              displayID: placement.displayID, edge: target.key.edge, slot: target.key.slot,
                                              expandedRect: placement.rect))
        }
        guard !activeDrawers.isEmpty else { return }
        activeDrawerLayoutID = layout.id
        log("Started \(activeDrawers.count) edge drawer(s)")
        drawerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                updateDrawers()
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }

    private func updateDrawers() {
        guard !snapOverlayActive else { return }
        let focused = WindowAccess.focusedWindowID()
        for index in activeDrawers.indices {
            let expanded = activeDrawers[index].windowID == focused
            guard expanded != activeDrawers[index].expanded,
                  let display = displays.first(where: { $0.id == activeDrawers[index].displayID }) else { continue }
            let drawer = activeDrawers[index]
            guard let target = restingTarget(for: drawer.edge, slot: drawer.slot, display: display) else { continue }
            if WindowAccess.setDrawerFrame(edge: target.key.edge, expanded: expanded, display: display,
                                            restingFrame: target.frame,
                                            expandedRect: drawer.expandedRect,
                                            windowID: drawer.windowID, bundleID: drawer.bundleID) {
                activeDrawers[index].expanded = expanded
                log("\(expanded ? "Expanded" : "Collapsed") drawer: \(drawer.bundleID)")
            }
        }
    }

    func updateRect(windowID: UUID, rect: UnitRect) {
        guard let layoutIndex = selectedLayoutIndex,
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == windowID }) else { return }
        var adjusted = rect
        adjusted.clamp()
        state.layouts[layoutIndex].windows[windowIndex].rect = adjusted
        state.layouts[layoutIndex].savedAt = .now
    }

    // Called after a snap commits. Keeps a running drawer in step and, with recordSnaps on,
    // writes the snapped cells into the selected layout's matching placement (no gap).
    func snapCommitted(window: AXUIElement, rect: UnitRect, display: DisplayInfo) {
        let windowID = WindowAccess.windowID(of: window)
        if windowID != 0, let index = activeDrawers.firstIndex(where: { $0.windowID == windowID }) {
            activeDrawers[index].expandedRect = rect
        }
        guard state.preferences.recordSnaps else { return }
        guard let layoutIndex = selectedLayoutIndex,
              let windowIndex = WindowAccess.placementIndex(of: window, in: state.layouts[layoutIndex].windows) else {
            log("Snap not recorded: no matching placement in the selected layout")
            return
        }
        let id = state.layouts[layoutIndex].windows[windowIndex].id
        if state.layouts[layoutIndex].windows[windowIndex].displayID != display.id { moveWindow(id, to: display.id) }
        updateRect(windowID: id, rect: rect)
        log("Snap recorded for \(state.layouts[layoutIndex].windows[windowIndex].appName)")
    }

    func captureFocusedWindow() {
        accessibilityTrusted = WindowAccess.trusted
        guard accessibilityTrusted else { WindowAccess.requestPermission(); status = "Accessibility is not trusted for this build"; log(status); return }
        guard let layoutIndex = selectedLayoutIndex else { status = "Select a layout first"; log(status); return }
        guard let window = WindowAccess.focusedWindow(),
              var placement = WindowAccess.placement(for: window, displays: displays) else {
            status = "No focused window to capture"
            log(status)
            return
        }
        if let existing = WindowAccess.placementIndex(of: window, in: state.layouts[layoutIndex].windows) {
            let id = state.layouts[layoutIndex].windows[existing].id
            if state.layouts[layoutIndex].windows[existing].displayID != placement.displayID { moveWindow(id, to: placement.displayID) }
            updateRect(windowID: id, rect: placement.rect)
            selectedWindowID = id
            status = "Updated \(placement.appName) in ‘\(state.layouts[layoutIndex].name)’"
        } else {
            let slots = state.layouts[layoutIndex].spaces ?? []
            placement.spaceID = slots.first(where: { $0.id == selectedSpaceID && $0.displayID == placement.displayID })?.id
                ?? slots.first(where: { $0.displayID == placement.displayID })?.id
            state.layouts[layoutIndex].windows.append(placement)
            state.layouts[layoutIndex].savedAt = .now
            selectedWindowID = placement.id
            status = "Captured \(placement.appName) into ‘\(state.layouts[layoutIndex].name)’"
        }
        log(status)
    }

    func grid(for display: DisplayInfo) -> GridSettings {
        state.preferences.grids[display.id] ?? .smart(for: display)
    }

    func setGridPreset(_ preset: String, for display: DisplayInfo) {
        var setting = grid(for: display)
        let dimensions: (Int, Int)
        switch preset {
        case "4x4": dimensions = (4, 4)
        case "8x4": dimensions = (8, 4)
        case "16x4": dimensions = (16, 4)
        case "16x9": dimensions = (16, 9)
        case "smart":
            let smart = GridSettings.smart(for: display)
            dimensions = (smart.columns, smart.rows)
        default: dimensions = (setting.columns, setting.rows)
        }
        setting.columns = dimensions.0
        setting.rows = dimensions.1
        setting.preset = preset
        state.preferences.grids[display.id] = setting
        log("Grid for \(display.name): \(setting.columns)×\(setting.rows)")
    }

    func gridGeometry(for display: DisplayInfo) -> GridGeometry {
        GridGeometry(grid(for: display), display: display)
    }

    func setGridDimensions(columns: Int? = nil, rows: Int? = nil, for display: DisplayInfo) {
        var setting = grid(for: display)
        let effective = gridGeometry(for: display)
        setting.columns = effective.columns
        setting.rows = effective.rows
        if let columns { setting.columns = min(32, max(2, columns)) }
        if let rows { setting.rows = min(32, max(2, rows)) }
        setting.preset = "custom"
        state.preferences.grids[display.id] = setting
    }

    func setSnapToGrid(_ enabled: Bool, for display: DisplayInfo) {
        var setting = grid(for: display)
        setting.snapToGrid = enabled
        state.preferences.grids[display.id] = setting
    }

    func setMarkers(halves: Bool? = nil, thirds: Bool? = nil, for display: DisplayInfo) {
        var setting = grid(for: display)
        if let halves { setting.showHalfMarkers = halves }
        if let thirds { setting.showThirdMarkers = thirds }
        state.preferences.grids[display.id] = setting
    }

    func resetGrid(for display: DisplayInfo) {
        state.preferences.grids[display.id] = .smart(for: display)
        log("Grid reset for \(display.name)")
    }

    var availableApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (id: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func addApp() {
        guard let app = availableApps.first(where: { $0.id == appToAdd }),
              let displayID = selectedDisplayID else { return }
        if selectedLayoutID == nil {
            createBlankLayout()
        }
        ensureSelectedSpace()
        guard let index = selectedLayoutIndex else { return }
        let count = state.layouts[index].windows.filter { $0.bundleID == app.id }.count
        var placement = WindowPlacement(bundleID: app.id, appName: app.name, title: "", ordinal: count,
                                        displayID: displayID,
                                        rect: UnitRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        placement.spaceID = selectedSpaceID
        state.layouts[index].windows.append(placement)
        selectedWindowID = placement.id
        log("Added \(app.name) to layout")
    }

    func moveWindow(_ id: UUID, to displayID: String) {
        guard let layoutIndex = selectedLayoutIndex,
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == id }) else { return }
        state.layouts[layoutIndex].windows[windowIndex].displayID = displayID
        if let slot = state.layouts[layoutIndex].spaces?.first(where: { $0.displayID == displayID }) {
            state.layouts[layoutIndex].windows[windowIndex].spaceID = slot.id
        }
    }

    func deleteSelectedLayout() {
        guard let id = selectedLayoutID else { return }
        if activeDrawerLayoutID == id {
            drawerTask?.cancel()
            drawerTask = nil
            activeDrawers = []
            activeDrawerLayoutID = nil
        }
        state.layouts.removeAll { $0.id == id }
        state.preferences.preferredLayouts = state.preferences.preferredLayouts.filter { $0.value != id }
        selectedLayoutID = layoutForEditor?.id
        ensureSelectedSpace()
        ensureSelectedWindow()
    }

    func assignedLayoutID(mode: String, displaySet: String) -> UUID? {
        state.preferences.preferredLayouts[assignmentKey(mode, displaySet)]
    }

    // Writes or clears the layout a Focus mode uses for a monitor set (the same preferredLayouts data).
    func assign(_ layout: SavedLayout?, mode: String, displaySet: String) {
        let key = assignmentKey(mode, displaySet)
        if let layout {
            guard layout.displaySet == displaySet else { return }
            state.preferences.preferredLayouts[key] = layout.id
            log("Assigned ‘\(layout.name)’ to \(mode) for \(displaySet == self.displaySet ? "current displays" : "another display set")")
        } else if state.preferences.preferredLayouts.removeValue(forKey: key) != nil {
            log("Cleared \(mode) assignment for \(displaySet == self.displaySet ? "current displays" : "another display set")")
        }
    }

    func assignedModes(of layout: SavedLayout) -> [String] {
        let suffix = "|\(layout.displaySet)"
        return state.preferences.preferredLayouts.compactMap { key, id in
            id == layout.id && key.hasSuffix(suffix) ? String(key.dropLast(suffix.count)) : nil
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // Every display set with a saved layout, plus the connected set, the connected set first.
    var monitorSets: [String] {
        var sets = [displaySet]
        for layout in state.layouts where !sets.contains(layout.displaySet) { sets.append(layout.displaySet) }
        return sets
    }

    func layouts(forDisplaySet set: String) -> [SavedLayout] {
        state.layouts.filter { $0.displaySet == set }.sorted { $0.savedAt > $1.savedAt }
    }

    func displayNames(forDisplaySet set: String) -> [String] {
        set.split(separator: "+").map { id in
            displays.first { $0.id == id }?.name ?? "Disconnected display \(id.prefix(4))"
        }
    }

    var appliedLayout: SavedLayout? { activeLayout }
    var activeDrawerCount: Int { activeDrawers.count }

    func duplicateSelectedLayout() {
        guard var layout = selectedLayout else { return }
        layout.id = UUID()
        layout.name += " copy"
        layout.savedAt = .now
        state.layouts.append(layout)
        selectedLayoutID = layout.id
        ensureSelectedSpace()
        log("Duplicated ‘\(layout.name)’")
    }

    func addMode() {
        let name = newModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !state.preferences.modes.contains(name) else { return }
        state.preferences.modes.append(name)
        newModeName = ""
    }

    func modeChanged() {
        selectedLayoutID = layoutForEditor?.id
        ensureSelectedSpace()
        ensureSelectedWindow()
        log("Mode: \(currentMode)")
    }

    func updateFocusMonitoring() {
        focusTask?.cancel()
        focusTask = nil
        guard state.preferences.focusModesEnabled else { modeChanged(); return }
        focusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let filter = try await LayoutFocusFilter.current
                    lastFocusError = nil
                    applyFocusProfile(filter.profile)
                } catch SetFocusFilterIntentError.notFound {
                    lastFocusError = nil
                    applyFocusProfile(nil)
                } catch {
                    let message = error.localizedDescription
                    if lastFocusError != message {
                        lastFocusError = message
                        log("Focus filter check failed: \(message)")
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func applyFocusProfile(_ profile: String?) {
        let name = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Default"
        guard mode != state.preferences.selectedMode else { return }
        if !state.preferences.modes.contains(mode) { state.preferences.modes.append(mode) }
        state.preferences.selectedMode = mode
        modeChanged()
        log("Automatic restore: Focus changed to \(mode)")
        restoreLatest()
    }

    func ensureSelectedWindow() {
        guard let layout = selectedLayout else { selectedWindowID = nil; return }
        let candidates = layout.windows.filter { $0.spaceID == selectedSpaceID }
        if !candidates.contains(where: { $0.id == selectedWindowID }) {
            selectedWindowID = candidates.first?.id
        }
    }

    private func persist() {
        guard didLoadState else { return }
        guard let data = try? JSONEncoder().encode(state) else { status = "Could not encode layouts"; return }
        do { try data.write(to: fileURL, options: .atomic) }
        catch { status = "Could not save layouts: \(error.localizedDescription)"; log(status) }
    }
}

private let displayCallback: CGDisplayReconfigurationCallBack = { displayID, flags, context in
    guard let context else { return }
    let store = Unmanaged<LayoutStore>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in store.displayEvent(id: displayID, flags: flags) }
}
