import AppKit
import AppIntents
import CoreGraphics
import Foundation
import Observation
import SpaceBridge

@MainActor @Observable final class LayoutStore {
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
    private var debounce: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var lastFocusError: String?
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenLayout", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("layouts.json")
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(StoredState.self, from: data) {
            state = loaded
        }
        migrateLegacyAssignments()
        migrateLegacySpaces()
        refreshDisplays(reason: "Startup")
        refreshFocusNames()
        log("Accessibility trusted: \(accessibilityTrusted)")
        log("Space move operation available: \(SLCanMoveWindows())")
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let error = CGDisplayRegisterReconfigurationCallback(displayCallback, pointer)
        log(error == .success ? "Display callback registered" : "Display callback registration failed: \(error.rawValue)")
        updateFocusMonitoring()
    }

    var displaySet: String { displays.map(\.id).sorted().joined(separator: "+") }
    var currentMode: String { state.preferences.focusModesEnabled ? state.preferences.selectedMode : "Default" }
    var relevantLayouts: [SavedLayout] { state.layouts.filter { $0.displaySet == displaySet } }
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

    private func migrateLegacySpaces() {
        for layoutIndex in state.layouts.indices where state.layouts[layoutIndex].spaces == nil {
            let displayIDs = Array(Set(state.layouts[layoutIndex].windows.map(\.displayID))).sorted()
            let slots = displayIDs.map { SpaceSlot(displayID: $0, name: "Desktop 1") }
            state.layouts[layoutIndex].spaces = slots
            for windowIndex in state.layouts[layoutIndex].windows.indices {
                let displayID = state.layouts[layoutIndex].windows[windowIndex].displayID
                state.layouts[layoutIndex].windows[windowIndex].spaceID = slots.first(where: { $0.displayID == displayID })?.id
            }
        }
    }

    func spaces(for display: DisplayInfo) -> [SpaceSlot] {
        selectedLayout?.spaces?.filter { $0.displayID == display.id } ?? []
    }

    var selectedSpace: SpaceSlot? { selectedLayout?.spaces?.first { $0.id == selectedSpaceID } }
    var canRemoveSelectedSpace: Bool {
        guard let slot = selectedSpace, let spaces = selectedLayout?.spaces else { return false }
        let others = spaces.filter { $0.displayID == slot.displayID && $0.id != slot.id }
        return !others.isEmpty && (slot.kind != .desktop || others.contains { $0.kind == .desktop })
    }

    func ensureSelectedSpace() {
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
              let displayID = selectedDisplayID else { selectedSpaceID = nil; return }
        if !(state.layouts[layoutIndex].spaces ?? []).contains(where: { $0.displayID == displayID }) {
            var slots = state.layouts[layoutIndex].spaces ?? []
            slots.append(SpaceSlot(displayID: displayID, name: "Desktop 1"))
            state.layouts[layoutIndex].spaces = slots
        }
        let slots = state.layouts[layoutIndex].spaces ?? []
        if !slots.contains(where: { $0.id == selectedSpaceID && $0.displayID == displayID }) {
            selectedSpaceID = slots.first(where: { $0.displayID == displayID })?.id
        }
    }

    func addSpace(kind: SpaceKind) {
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
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

    func moveSelectedSpace(_ offset: Int) {
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
              var slots = state.layouts[layoutIndex].spaces,
              let source = slots.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        let indices = slots.indices.filter { slots[$0].displayID == slots[source].displayID }
        guard let position = indices.firstIndex(of: source), indices.indices.contains(position + offset) else { return }
        slots.swapAt(source, indices[position + offset])
        state.layouts[layoutIndex].spaces = slots
    }

    func removeSelectedSpace() {
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
              var slots = state.layouts[layoutIndex].spaces,
              let selected = slots.first(where: { $0.id == selectedSpaceID }) else { return }
        let sameDisplay = slots.filter { $0.displayID == selected.displayID && $0.id != selected.id }
        if selected.kind == .desktop && !sameDisplay.contains(where: { $0.kind == .desktop }) { return }
        guard let destination = sameDisplay.first(where: { $0.kind == .desktop }) ?? sameDisplay.first else { return }
        for index in state.layouts[layoutIndex].windows.indices where state.layouts[layoutIndex].windows[index].spaceID == selected.id {
            state.layouts[layoutIndex].windows[index].spaceID = destination.id
        }
        slots.removeAll { $0.id == selected.id }
        state.layouts[layoutIndex].spaces = slots
        selectedSpaceID = destination.id
        ensureSelectedWindow()
    }

    func moveWindowToSpace(_ windowID: UUID, spaceID: UUID) {
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
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
            if self?.state.preferences.autoRestoreOnDisplayChange == true { self?.restoreLatest() }
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

    func capture() {
        accessibilityTrusted = WindowAccess.trusted
        guard accessibilityTrusted else { WindowAccess.requestPermission(); status = "Accessibility is not trusted for this build"; log(status); return }
        var windows = WindowAccess.capture(displays: displays)
        let slots = displays.map { SpaceSlot(displayID: $0.id, name: "Desktop 1") }
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
        let slots = displays.map { SpaceSlot(displayID: $0.id, name: "Desktop 1") }
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
        guard let index = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }) else { return }
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
        let multiSpace = slotsByDisplay.values.contains { $0.count > 1 }
        if multiSpace && !SLCanMoveWindows() {
            status = "Moving windows between Spaces is unavailable on this macOS build"
            log(status)
            return
        }
        if multiSpace {
            let result = WindowAccess.restoreAcrossSpaces(layout.windows, displays: displays, targetSpaces: targets)
            status = "Restored \(result.moved) windows; skipped \(result.skipped); Space moves failed \(result.spaceFailed)"
        } else {
            let result = WindowAccess.restore(layout.windows, displays: displays)
            status = "Restored \(result.moved) windows; skipped \(result.skipped)"
        }
        log("Restore ‘\(layout.name)’: \(status)")
    }

    func updateRect(windowID: UUID, rect: UnitRect) {
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == windowID }) else { return }
        var adjusted = rect
        adjusted.clamp()
        state.layouts[layoutIndex].windows[windowIndex].rect = adjusted
        state.layouts[layoutIndex].savedAt = .now
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

    func setGridDimensions(columns: Int? = nil, rows: Int? = nil, for display: DisplayInfo) {
        var setting = grid(for: display)
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
        guard let index = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }) else { return }
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
        guard let layoutIndex = state.layouts.firstIndex(where: { $0.id == selectedLayoutID }),
              let windowIndex = state.layouts[layoutIndex].windows.firstIndex(where: { $0.id == id }) else { return }
        state.layouts[layoutIndex].windows[windowIndex].displayID = displayID
        if let slot = state.layouts[layoutIndex].spaces?.first(where: { $0.displayID == displayID }) {
            state.layouts[layoutIndex].windows[windowIndex].spaceID = slot.id
        }
    }

    func deleteSelectedLayout() {
        guard let id = selectedLayoutID else { return }
        state.layouts.removeAll { $0.id == id }
        state.preferences.preferredLayouts = state.preferences.preferredLayouts.filter { $0.value != id }
        selectedLayoutID = layoutForEditor?.id
        ensureSelectedSpace()
        ensureSelectedWindow()
    }

    func isAssigned(_ layout: SavedLayout, to mode: String) -> Bool {
        state.preferences.preferredLayouts[assignmentKey(mode, displaySet)] == layout.id
    }

    func setAssigned(_ assigned: Bool, layout: SavedLayout, to mode: String) {
        guard layout.displaySet == displaySet else { return }
        let key = assignmentKey(mode, displaySet)
        if assigned { state.preferences.preferredLayouts[key] = layout.id }
        else if state.preferences.preferredLayouts[key] == layout.id { state.preferences.preferredLayouts.removeValue(forKey: key) }
        log("\(assigned ? "Assigned" : "Removed") ‘\(layout.name)’ \(assigned ? "to" : "from") \(mode) for current displays")
    }

    func assignSelectedToAllFocuses() {
        guard let layout = selectedLayout else { return }
        for mode in selectableFocusNames { setAssigned(true, layout: layout, to: mode) }
    }

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
                do {
                    let filter = try await LayoutFocusFilter.current
                    self?.lastFocusError = nil
                    self?.applyFocusProfile(filter.profile)
                } catch SetFocusFilterIntentError.notFound {
                    self?.lastFocusError = nil
                    self?.applyFocusProfile(nil)
                } catch {
                    let message = error.localizedDescription
                    if self?.lastFocusError != message {
                        self?.lastFocusError = message
                        self?.log("Focus filter check failed: \(message)")
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
