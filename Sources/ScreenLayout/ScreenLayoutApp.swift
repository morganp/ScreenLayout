import AppKit
import SwiftUI

@main struct ScreenLayoutApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller
    private let store = LayoutStore.shared

    var body: some Scene {
        WindowGroup("ScreenLayout", id: "main") {
            ContentView(store: store, controller: controller)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(AppController.launchedAtLogin ? .suppressed : .presented)

        MenuBarExtra {
            MenuBarContent(store: store, controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarLabel: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "rectangle.3.group")
            .task { controller.openWindowAction = { openWindow(id: "main") } }
    }
}

struct MenuBarContent: View {
    @Bindable var store: LayoutStore
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = store.loginItemTick
        Text(store.status)
        Text(LoginItem.statusText)
        Divider()
        Button("Restore selected layout", action: store.restoreSelected)
            .disabled(store.selectedLayout == nil)
        Button("Restore matching layout for current displays", action: store.restoreLatest)
        Button("Snap window…") { SnapController.shared.showAfterMenu() }
        Button("Capture focused window into selected layout") { SnapController.shared.captureFocusedWindowAfterMenu() }
            .disabled(store.selectedLayout == nil)
        Button("Open ScreenLayout") {
            controller.openWindowAction = { openWindow(id: "main") }
            controller.showMainWindow()
        }
        Divider()
        Toggle("Launch at login", isOn: Binding(
            get: { LoginItem.isOn }, set: { store.setLaunchAtLogin($0) }))
        if LoginItem.status == .requiresApproval {
            Button("Approve in System Settings…", action: LoginItem.openSystemSettings)
        }
        Toggle("Run in background", isOn: Binding(
            get: { store.state.preferences.runInBackground },
            set: { store.state.preferences.runInBackground = $0; controller.applyActivationPolicy() }))
        Divider()
        Button("Quit ScreenLayout") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct ContentView: View {
    @Bindable var store: LayoutStore
    let controller: AppController
    @State private var tab = 0

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ScreenLayout").font(.title2.bold())
                Label("\(store.displays.count) connected displays", systemImage: "display.2")
                Toggle("Use macOS Focus filters", isOn: $store.state.preferences.focusModesEnabled)
                    .onChange(of: store.state.preferences.focusModesEnabled) { _, _ in store.updateFocusMonitoring() }
                if store.state.preferences.focusModesEnabled {
                    Text("Active layout profile: \(store.currentMode)")
                        .font(.subheadline)
                    Text(store.focusCatalogError == nil
                         ? "\(store.focusNames.count) Focus modes found. Add a ScreenLayout filter to each Focus you want to automate."
                         : "macOS blocks automatic listing here. Add Focus names below, then add a ScreenLayout filter to each Focus you want to automate.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Add Focus name", text: $store.newModeName).onSubmit { store.addMode() }
                        Button(action: store.addMode) { Image(systemName: "plus") }
                    }
                    Button("Refresh Focus list", action: store.refreshFocusNames)
                }
                Toggle("Restore on display change", isOn: $store.state.preferences.autoRestoreOnDisplayChange)
                let _ = store.loginItemTick
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isOn }, set: { store.setLaunchAtLogin($0) }))
                Text(LoginItem.statusText).font(.caption).foregroundStyle(.secondary)
                if LoginItem.status == .requiresApproval {
                    Button("Approve in System Settings…", action: LoginItem.openSystemSettings)
                }
                Toggle("Run in background", isOn: $store.state.preferences.runInBackground)
                    .onChange(of: store.state.preferences.runInBackground) { _, _ in controller.applyActivationPolicy() }
                Text("When on, closing the window hides the Dock icon and keeps ScreenLayout in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Current display set").font(.headline)
                ForEach(store.displays) { display in
                    Label(display.name, systemImage: "display")
                        .font(.subheadline)
                }
                Text(NSScreen.screensHaveSeparateSpaces
                     ? "Displays have separate Spaces: On"
                     : "Displays have separate Spaces: Off")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh displays", action: { store.refreshDisplays() })
                Button("Refresh Spaces", action: store.refreshSpaces)
                Spacer()
                if !store.accessibilityTrusted {
                    Button("Check Accessibility access") { store.refreshDisplays(reason: "Permission check") }
                    Button("Open Accessibility permission prompt", action: WindowAccess.requestPermission)
                } else {
                    Label("Accessibility access ready", systemImage: "checkmark.shield")
                        .font(.caption)
                }
                Text(store.status).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 240)
        } detail: {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    Text("Layouts").tag(0)
                    Text("Drawers").tag(1)
                    Text("Snap").tag(3)
                    Text("Debug events").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 520)
                .padding()
                Divider()
                if tab == 0 { LayoutEditor(store: store) }
                else if tab == 1 { DrawerEditor(store: store) }
                else if tab == 3 { SnapSettings(store: store, tab: $tab) }
                else { DebugView(store: store) }
            }
        }
    }
}

struct LayoutEditor: View {
    @Bindable var store: LayoutStore
    @State private var showAllApps = false
    @State private var showFocusAssignments = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Saved layout", selection: $store.selectedLayoutID) {
                    Text("Choose layout").tag(UUID?.none)
                    ForEach(store.relevantLayouts.sorted(by: { $0.savedAt > $1.savedAt })) { layout in
                        Text("\(layout.name) · \(layout.windows.count) windows").tag(Optional(layout.id))
                    }
                }
                Button("New blank layout", action: store.createBlankLayout)
                Button("Capture screen as new layout", action: store.capture)
            }
            HStack {
                TextField("Layout name", text: Binding(
                    get: { store.selectedLayout?.name ?? "" },
                    set: { store.renameSelectedLayout($0) }))
                    .frame(maxWidth: 260)
                    .disabled(store.selectedLayout == nil)
                Button("Restore this layout", action: store.restoreSelected)
                    .disabled(store.selectedLayout == nil)
                Button("Save as copy", action: store.duplicateSelectedLayout)
                    .disabled(store.selectedLayout == nil)
                Button("Delete layout", role: .destructive) { confirmDelete = true }
                    .disabled(store.selectedLayout == nil)
                    .confirmationDialog("Delete ‘\(store.selectedLayout?.name ?? "")’?", isPresented: $confirmDelete) {
                        Button("Delete layout", role: .destructive, action: store.deleteSelectedLayout)
                    } message: {
                        Text("This removes the saved layout and its Focus assignments.")
                    }
                Text("Edits save automatically")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Focus modes…") { showFocusAssignments = true }
                    .disabled(store.selectedLayout == nil)
                    .popover(isPresented: $showFocusAssignments) {
                        if let layout = store.selectedLayout {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Apply ‘\(layout.name)’ to Focus modes").font(.headline)
                                Text("For this connected monitor set. Select several modes to share this layout; duplicate it first for an independent copy.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Select all") { store.assignSelectedToAllFocuses() }
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(store.selectableFocusNames, id: \.self) { mode in
                                            Toggle(mode, isOn: Binding(
                                                get: { store.isAssigned(layout, to: mode) },
                                                set: { store.setAssigned($0, layout: layout, to: mode) }))
                                        }
                                    }
                                }
                                Button("Done") { showFocusAssignments = false }
                            }
                            .padding()
                            .frame(width: 330, height: 350)
                        }
                    }
                Picker("Edit display", selection: $store.selectedDisplayID) {
                    ForEach(store.displays) { display in Text(display.name).tag(Optional(display.id)) }
                }
            }
            if let layout = store.selectedLayout, let display = store.displays.first(where: { $0.id == store.selectedDisplayID }) {
                HStack {
                    Picker("Space in layout", selection: $store.selectedSpaceID) {
                        ForEach(store.spaces(for: display)) { slot in
                            Text(slot.name).tag(Optional(slot.id))
                        }
                    }
                    .onChange(of: store.selectedSpaceID) { _, _ in store.ensureSelectedWindow() }
                    Button("Add desktop") { store.addSpace(kind: .desktop) }
                    Button("Add full screen") { store.addSpace(kind: .fullScreen) }
                    Button("Move left") { store.moveSelectedSpace(-1) }
                        .disabled(store.selectedSpaceID == store.spaces(for: display).first?.id)
                    Button("Move right") { store.moveSelectedSpace(1) }
                        .disabled(store.selectedSpaceID == store.spaces(for: display).last?.id)
                    Button("Remove Space") { store.removeSelectedSpace() }
                        .disabled(!store.canRemoveSelectedSpace)
                }
                .font(.subheadline)
                HStack {
                    Text("Desktop Spaces in layout: \(store.requiredDesktopSpaces(for: layout, display: display))")
                    if let available = store.desktopSpaceCount(for: display) {
                        let missing = max(0, store.requiredDesktopSpaces(for: layout, display: display) - available)
                        Text(missing == 0 ? "\(available) available" : "\(available) available · \(missing) missing")
                            .foregroundStyle(missing == 0 ? Color.secondary : Color.orange)
                    } else {
                        Text("Space count unavailable").foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
                Text("Desktop slots use the existing Spaces on this display in their shown order. Restore moves their windows to the matching Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Add running app", selection: $store.appToAdd) {
                        Text("Choose app").tag("")
                        ForEach(store.availableApps, id: \.id) { app in Text(app.name).tag(app.id) }
                    }
                    Button("Add to grid", action: store.addApp).disabled(store.appToAdd.isEmpty)
                }
                HStack {
                    Picker("App to position", selection: $store.selectedWindowID) {
                        ForEach(layout.windows.filter { $0.spaceID == store.selectedSpaceID }) { window in
                            Text("\(window.appName): \(window.title.isEmpty ? "Untitled" : window.title)").tag(Optional(window.id))
                        }
                    }
                    Toggle("Show all apps", isOn: $showAllApps)
                        .fixedSize()
                }
                if let selected = store.selectedWindowID {
                    HStack {
                        Picker("Window behavior", selection: Binding(
                            get: { layout.windows.first(where: { $0.id == selected })?.drawer },
                            set: { store.setDrawer($0, for: selected) })) {
                                Text("Normal").tag(DrawerEdge?.none)
                                let current = layout.windows.first(where: { $0.id == selected })
                                let rule = store.cornerRule(forDisplayID: current?.displayID ?? display.id)
                                let displayID = current?.displayID ?? display.id
                                let enabled = DrawerEdge.legal(for: rule).filter { store.isDrawerEnabled($0, displayID: displayID) }
                                ForEach(enabled, id: \.self) { edge in
                                    Text("\(edge.title) drawer").tag(Optional(edge))
                                }
                                if let saved = current?.drawer, !enabled.contains(saved) {
                                    if !saved.isLegal(for: rule), store.isDrawerEnabled(saved.resolved(for: rule), displayID: displayID) {
                                        Text("\(saved.title) drawer (using \(saved.resolved(for: rule).title.lowercased()))").tag(Optional(saved))
                                    } else {
                                        Text("\(saved.title) drawer (disabled)").tag(Optional(saved))
                                    }
                                }
                            }
                            .frame(width: 320)
                        drawerSlotPicker(layout: layout, selected: selected)
                    }
                    if let window = layout.windows.first(where: { $0.id == selected }), let key = store.drawerKey(for: window) {
                        let sharers = store.drawerOccupants(of: key, displayID: window.displayID, excluding: selected, in: layout)
                        if !sharers.isEmpty {
                            Text("Shares this slot with \(sharers.map(\.appName).joined(separator: ", ")). Only the focused one expands.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                GridControls(store: store, display: display)
                Text("Drag the blue app area to move it; drag its lower-right handle to resize. Grid settings are saved for this monitor.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.selectedSpace?.kind == .fullScreen {
                    Text("Full-screen slot. Add one app here; its saved grid position is ignored when Space application is available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GridCanvas(store: store, layout: layout, display: display, showAllApps: showAllApps)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    if let selected = store.selectedWindowID {
                        Picker("Move to Space", selection: Binding(
                            get: { layout.windows.first(where: { $0.id == selected })?.spaceID },
                            set: { if let slotID = $0 { store.moveWindowToSpace(selected, spaceID: slotID) } })) {
                                ForEach(layout.spaces ?? []) { slot in
                                    Text("\(slot.name) · \(store.displays.first(where: { $0.id == slot.displayID })?.name ?? "Display")")
                                        .tag(Optional(slot.id))
                                }
                            }
                        Picker("Move to display", selection: Binding(
                            get: { layout.windows.first(where: { $0.id == selected })?.displayID ?? display.id },
                            set: { store.moveWindow(selected, to: $0) })) {
                                ForEach(store.displays) { screen in Text(screen.name).tag(screen.id) }
                            }
                    }
                }
                .onAppear { store.ensureSelectedSpace(); store.ensureSelectedWindow() }
                .onChange(of: store.selectedLayoutID) { _, _ in store.ensureSelectedSpace(); store.ensureSelectedWindow() }
                .onChange(of: store.selectedDisplayID) { _, _ in store.ensureSelectedSpace(); store.ensureSelectedWindow() }
            } else {
                ContentUnavailableView("No layout selected", systemImage: "rectangle.on.rectangle",
                                       description: Text("Create a blank layout or capture the current screen to start."))
            }
        }
        .padding()
    }
}

extension LayoutEditor {
    // Slot choice for the selected window's drawer; shown only when its edge has several slots.
    @ViewBuilder
    func drawerSlotPicker(layout: SavedLayout, selected: UUID) -> some View {
        if let window = layout.windows.first(where: { $0.id == selected }), let edge = window.drawer,
           let display = store.displays.first(where: { $0.id == window.displayID }) {
            let resolved = store.usableDrawerEdge(edge, displayID: display.id) ?? edge
            let count = store.effectiveDrawerCount(for: resolved, display: display)
            if count > 1 {
                let current = store.drawerKey(for: window)?.slot ?? 0
                Picker("Slot", selection: Binding(
                    get: { current },
                    set: { store.setDrawerSlot($0, for: selected) })) {
                        ForEach(0..<count, id: \.self) { slot in
                            let others = store.drawerOccupants(of: DrawerKey(edge: resolved, slot: slot), displayID: window.displayID,
                                                               excluding: selected, in: layout)
                            Text(others.isEmpty ? "Slot \(slot + 1)" : "Slot \(slot + 1) · in use: \(others.map(\.appName).joined(separator: ", "))")
                                .tag(slot)
                        }
                    }
                    .frame(width: 280)
            }
        }
    }
}

struct DrawerEditor: View {
    @Bindable var store: LayoutStore
    @State private var selectedEdge: DrawerEdge = .right
    @State private var selectedSlot = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drawers").font(.title2.bold())
            if let display = store.displays.first(where: { $0.id == store.selectedDisplayID }) {
                let rule = store.cornerRule(for: display)
                let edge = selectedEdge.resolved(for: rule)
                let requested = store.drawerCount(for: edge, display: display)
                let slots = store.effectiveDrawerCount(for: edge, display: display)
                let slot = max(0, min(selectedSlot, slots - 1))
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Monitor", selection: $store.selectedDisplayID) {
                            ForEach(store.displays) { screen in Text(screen.name).tag(Optional(screen.id)) }
                        }
                        Picker("Corners", selection: Binding(
                            get: { rule },
                            set: { store.setCornerRule($0, for: display) })) {
                                ForEach(CornerRule.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        Text(rule.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 440)
                    VStack(spacing: 4) {
                        ForEach([[DrawerEdge.topLeft, .top, .topRight], [.left, nil, .right], [.bottomLeft, .bottom, .bottomRight]], id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(row.indices, id: \.self) { column in
                                    if let position = row[column] {
                                        Button(position.title) { selectedEdge = position }
                                            .disabled(!position.isLegal(for: rule))
                                            .opacity(store.isDrawerEnabled(position, displayID: display.id) ? 1 : 0.5)
                                            .frame(width: 92, height: 30)
                                            .background(edge == position ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1),
                                                        in: RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Color.clear.frame(width: 92, height: 30)
                                    }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(slots > 1 ? "\(edge.title) drawer, slot \(slot + 1)" : "\(edge.title) drawer").font(.headline)
                        if edge.isCorner {
                            Toggle("Corner drawer", isOn: Binding(
                                get: { requested > 0 },
                                set: { store.setDrawerCount($0 ? 1 : 0, for: edge, display: display) }))
                        } else {
                            Stepper(requested == 0 ? "Drawers on this edge: off" : "Drawers on this edge: \(requested)", value: Binding(
                                get: { requested },
                                set: { store.setDrawerCount($0, for: edge, display: display) }), in: 0...DrawerGeometry.maxSlots)
                            if slots > 1 {
                                HStack(spacing: 4) {
                                    ForEach(0..<slots, id: \.self) { index in
                                        Button("\(index + 1)") { selectedSlot = index }
                                            .frame(width: 30)
                                            .background(slot == index ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1),
                                                        in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            if slots < requested {
                                Text("The grid has room for \(slots) here; showing \(slots).")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Text(requested == 0 ? "Disabled: no strip and no reserved space."
                             : depthReadout(store.drawerSize(for: edge, display: display), edge: edge,
                                            geometry: store.gridGeometry(for: display)))
                            .monospacedDigit()
                        Button("Reset this drawer") { store.resetDrawerSize(for: edge, display: display) }
                            .disabled(!store.isDrawerConfigured(edge, display: display))
                    }
                }
                GridControls(store: store, display: display)
                DrawerCanvas(store: store, display: display, selected: DrawerKey(edge: edge, slot: slot)) { key in
                    if store.drawerCount(for: key.edge, display: display) == 0 { store.setDrawerCount(1, for: key.edge, display: display) }
                    selectedEdge = key.edge
                    selectedSlot = key.slot
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private func depthReadout(_ size: DrawerSize, edge: DrawerEdge, geometry: GridGeometry) -> String {
        func cells(_ fraction: Double, _ count: Int, _ unit: String) -> String {
            let value = fraction * Double(count)
            let text = abs(value - value.rounded()) < 0.05 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
            return "\(text) \(unit)\(text == "1" ? "" : "s")"
        }
        var cellParts: [String] = []
        var percentParts: [String] = []
        if edge.hasHorizontalDepth {
            cellParts.append(cells(size.width, geometry.columns, "column"))
            percentParts.append("\(Int((size.width * 100).rounded()))%")
        }
        if edge.hasVerticalDepth {
            cellParts.append(cells(size.height, geometry.rows, "row"))
            percentParts.append("\(Int((size.height * 100).rounded()))%")
        }
        return "\(cellParts.joined(separator: " × ")) · \(percentParts.joined(separator: " × "))"
    }
}

// The monitor's shared grid with every enabled drawer strip drawn on it, and faint dashed outlines
// where a position is off. Click a strip or outline to select it (an outline also enables it); click
// or drag elsewhere to set the selected drawer's depth from its edge. With Snap to grid on, the depth
// snaps to whole cells.
struct DrawerCanvas: View {
    @Bindable var store: LayoutStore
    let display: DisplayInfo
    let selected: DrawerKey
    let onSelect: (DrawerKey) -> Void
    @State private var grabbedOther: Bool?

    private func targets(in area: CGRect) -> [(key: DrawerKey, rect: CGRect, enabled: Bool)] {
        let rule = store.cornerRule(for: display)
        let rects = store.drawerRects(for: display, in: area)
        var result = rects.keys.sorted { ($0.edge.rawValue, $0.slot) < ($1.edge.rawValue, $1.slot) }
            .compactMap { key in rects[key].map { (key: key, rect: $0, enabled: true) } }
        for edge in DrawerEdge.legal(for: rule) where !store.isDrawerEnabled(edge, displayID: display.id) {
            let key = DrawerKey(edge: edge)
            if let rect = store.drawerRects(for: display, in: area, enabling: edge)[key] {
                result.append((key: key, rect: rect, enabled: false))
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / display.visibleFrame.width,
                            geometry.size.height / display.visibleFrame.height)
            let canvasSize = CGSize(width: display.visibleFrame.width * scale,
                                    height: display.visibleFrame.height * scale)
            let area = CGRect(origin: .zero, size: canvasSize)
            let items = targets(in: area)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.08))
                ForEach(items, id: \.key) { item in
                    let isSelected = item.key == selected
                    let multiple = item.enabled && items.contains { $0.enabled && $0.key.edge == item.key.edge && $0.key.slot > 0 }
                    let shape = RoundedRectangle(cornerRadius: 4)
                    Group {
                        if item.enabled {
                            shape.fill(Color.accentColor.opacity(isSelected ? 0.5 : 0.2))
                                .overlay(shape.stroke(Color.accentColor.opacity(isSelected ? 1 : 0.5), lineWidth: isSelected ? 2 : 1))
                        } else {
                            shape.fill(Color.accentColor.opacity(isSelected ? 0.12 : 0))
                                .overlay(shape.stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                                                      style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [5, 4])))
                        }
                    }
                    .overlay(Text(multiple ? "\(item.key.slot + 1)" : item.key.edge.title).font(.caption)
                        .foregroundStyle(item.enabled ? .secondary : .tertiary).lineLimit(1).padding(3))
                    .frame(width: item.rect.width, height: item.rect.height)
                    .offset(x: item.rect.minX, y: item.rect.minY)
                    .allowsHitTesting(false)
                }
                GridBackdrop(store: store, display: display)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if grabbedOther == nil {
                                let start = drag.startLocation
                                let hit = items.first { $0.key == selected && $0.rect.contains(start) }
                                    ?? items.first { $0.enabled && $0.rect.contains(start) }
                                    ?? items.first { $0.rect.contains(start) }
                                if let hit, hit.key != selected {
                                    grabbedOther = true
                                    onSelect(hit.key)
                                } else {
                                    grabbedOther = false
                                }
                            }
                            if grabbedOther == false { setDepth(at: drag.location, canvas: canvasSize) }
                        }
                        .onEnded { _ in grabbedOther = nil })
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func setDepth(at point: CGPoint, canvas: CGSize) {
        guard store.isDrawerEnabled(selected.edge, displayID: display.id) else { return }
        let grid = store.gridGeometry(for: display)
        let snap = store.grid(for: display).snapToGrid
        var size = store.drawerSize(for: selected.edge, display: display)
        func depth(_ position: Double, count: Int, fromFarSide: Bool) -> Double {
            let raw = min(1, max(0, fromFarSide ? 1 - position : position))
            guard snap else { return max(0.05, raw) }
            return Double(min(count, Int((raw * Double(count)).rounded(.down)) + 1)) / Double(count)
        }
        if selected.edge.hasHorizontalDepth {
            size.width = depth(point.x / canvas.width, count: grid.columns, fromFarSide: selected.edge.isRight)
        }
        if selected.edge.hasVerticalDepth {
            size.height = depth(point.y / canvas.height, count: grid.rows, fromFarSide: selected.edge.isBottom)
        }
        if size != store.drawerSize(for: selected.edge, display: display) || !store.isDrawerConfigured(selected.edge, display: display) {
            store.setDrawerSize(size, for: selected.edge, display: display)
        }
    }
}

// The grid lines and 1/2, 1/3 markers for a monitor, shared by the Layouts canvas and the Drawers canvas.
struct GridBackdrop: View {
    @Bindable var store: LayoutStore
    let display: DisplayInfo

    var body: some View {
        Canvas { context, size in
            let geometry = store.gridGeometry(for: display)
            let area = CGRect(origin: .zero, size: size)
            var path = Path()
            for column in 0..<geometry.columns {
                for row in 0..<geometry.rows {
                    path.addRect(geometry.cellRect(column: column, row: row, in: area))
                }
            }
            context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            let setting = store.grid(for: display)
            var markers = Path()
            for fraction in GridGeometry.markerFractions(halves: setting.showHalfMarkers, thirds: setting.showThirdMarkers) {
                let x = area.minX + area.width * fraction
                let y = area.minY + area.height * fraction
                markers.move(to: CGPoint(x: x, y: area.minY)); markers.addLine(to: CGPoint(x: x, y: area.maxY))
                markers.move(to: CGPoint(x: area.minX, y: y)); markers.addLine(to: CGPoint(x: area.maxX, y: y))
            }
            context.stroke(markers, with: .color(.accentColor.opacity(0.55)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

// One editor for a monitor's grid, shown in Layouts and in the Snap tab. Both read the same GridSettings.
struct GridControls: View {
    @Bindable var store: LayoutStore
    let display: DisplayInfo

    var body: some View {
        let geometry = store.gridGeometry(for: display)
        HStack {
            Picker("Grid", selection: Binding(
                get: { store.grid(for: display).preset },
                set: { store.setGridPreset($0, for: display) })) {
                    Text("Smart").tag("smart")
                    Text("4 × 4").tag("4x4")
                    Text("8 × 4").tag("8x4")
                    Text("16 × 4").tag("16x4")
                    Text("16 × 9").tag("16x9")
                    Text("Custom").tag("custom")
                }
                .frame(width: 170)
            Stepper("Columns: \(geometry.columns)", value: Binding(
                get: { geometry.columns },
                set: { store.setGridDimensions(columns: $0, for: display) }), in: 2...32)
            Stepper("Rows: \(geometry.rows)", value: Binding(
                get: { geometry.rows },
                set: { store.setGridDimensions(rows: $0, for: display) }), in: 2...32)
            Toggle("Snap to grid", isOn: Binding(
                get: { store.grid(for: display).snapToGrid },
                set: { store.setSnapToGrid($0, for: display) }))
                .fixedSize()
            Toggle("Show 1/2 markers", isOn: Binding(
                get: { store.grid(for: display).showHalfMarkers },
                set: { store.setMarkers(halves: $0, for: display) }))
                .fixedSize()
            Toggle("Show 1/3 markers", isOn: Binding(
                get: { store.grid(for: display).showThirdMarkers },
                set: { store.setMarkers(thirds: $0, for: display) }))
                .fixedSize()
            Button("Reset grid") { store.resetGrid(for: display) }
        }
        .font(.subheadline)
    }
}

struct GridCanvas: View {
    @Bindable var store: LayoutStore
    let layout: SavedLayout
    let display: DisplayInfo
    let showAllApps: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / display.visibleFrame.width,
                            geometry.size.height / display.visibleFrame.height)
            let canvasSize = CGSize(width: display.visibleFrame.width * scale,
                                    height: display.visibleFrame.height * scale)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.08))
                GridBackdrop(store: store, display: display)
                ForEach(layout.windows.filter { window in
                    guard window.displayID == display.id,
                          window.spaceID == store.selectedSpaceID else { return false }
                    if showAllApps { return true }
                    let selected = layout.windows.first { $0.id == store.selectedWindowID }
                    return window.id == selected?.id
                }) { window in
                    WindowTile(store: store, window: window, display: display, canvasSize: canvasSize)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct WindowTile: View {
    @Bindable var store: LayoutStore
    let window: WindowPlacement
    let display: DisplayInfo
    let canvasSize: CGSize
    @State private var dragStart: UnitRect?
    @State private var draftRect: UnitRect?
    @State private var horizontalSnapIndex: Int?
    @State private var verticalSnapIndex: Int?

    var body: some View {
        let rect = draftRect ?? window.rect
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(store.selectedWindowID == window.id ? 0.5 : 0.28))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { store.selectedWindowID = window.id }
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { gesture in previewMove(gesture.translation) }
                    .onEnded { _ in commitDrag() })
            Text("\(window.appName)\n\(window.title)")
                .font(.caption).lineLimit(2).padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.bold()).padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { gesture in previewResize(gesture.translation) }
                    .onEnded { _ in commitDrag() })
        }
        .frame(width: max(50, rect.width * canvasSize.width), height: max(40, rect.height * canvasSize.height))
        .position(x: (rect.x + rect.width / 2) * canvasSize.width,
                  y: (rect.y + rect.height / 2) * canvasSize.height)
    }

    private func beginDrag() -> UnitRect {
        if dragStart == nil {
            dragStart = window.rect
            store.selectedWindowID = window.id
        }
        return dragStart ?? window.rect
    }

    private func previewMove(_ translation: CGSize) {
        let start = beginDrag()
        var next = start
        next.x += translation.width / canvasSize.width
        next.y += translation.height / canvasSize.height
        let grid = store.grid(for: display)
        let geometry = store.gridGeometry(for: display)
        if grid.snapToGrid {
            if abs(translation.width) > 2 {
                next.x = snappedMoveOrigin(next.x, start: start.x, size: start.width,
                                           divisions: geometry.columns, previous: &horizontalSnapIndex)
            }
            if abs(translation.height) > 2 {
                next.y = snappedMoveOrigin(next.y, start: start.y, size: start.height,
                                           divisions: geometry.rows, previous: &verticalSnapIndex)
            }
        }
        next.clamp()
        draftRect = next
    }

    private func previewResize(_ translation: CGSize) {
        let start = beginDrag()
        var next = start
        next.width += translation.width / canvasSize.width
        next.height += translation.height / canvasSize.height
        let grid = store.grid(for: display)
        let geometry = store.gridGeometry(for: display)
        if grid.snapToGrid {
            if abs(translation.width) > 2 {
                if horizontalSnapIndex == nil { horizontalSnapIndex = Int(((start.x + start.width) * Double(geometry.columns)).rounded()) }
                let right = hystereticCell(next.x + next.width, previous: &horizontalSnapIndex,
                                           divisions: geometry.columns, allowed: 1...geometry.columns)
                next.width = max(1 / Double(geometry.columns), Double(right) / Double(geometry.columns) - next.x)
            }
            if abs(translation.height) > 2 {
                if verticalSnapIndex == nil { verticalSnapIndex = Int(((start.y + start.height) * Double(geometry.rows)).rounded()) }
                let bottom = hystereticCell(next.y + next.height, previous: &verticalSnapIndex,
                                            divisions: geometry.rows, allowed: 1...geometry.rows)
                next.height = max(1 / Double(geometry.rows), Double(bottom) / Double(geometry.rows) - next.y)
            }
        }
        next.clamp()
        draftRect = next
    }

    private func hystereticCell(_ value: Double, previous: inout Int?, divisions: Int,
                                allowed: ClosedRange<Int>) -> Int {
        let scaled = value * Double(divisions)
        let current = min(allowed.upperBound, max(allowed.lowerBound, previous ?? Int(scaled.rounded())))
        let next = abs(scaled - Double(current)) > 0.65 ? Int(scaled.rounded()) : current
        let clamped = min(allowed.upperBound, max(allowed.lowerBound, next))
        previous = clamped
        return clamped
    }

    private func snappedMoveOrigin(_ value: Double, start: Double, size: Double,
                                   divisions: Int, previous: inout Int?) -> Double {
        let limit = max(0, 1 - size)
        let lastGridLine = Int(floor(limit * Double(divisions)))
        var positions = (0...lastGridLine).map { Double($0) / Double(divisions) }
        if limit - positions[positions.count - 1] > 0.000001 { positions.append(limit) }

        let startingIndex = positions.indices.min { abs(positions[$0] - start) < abs(positions[$1] - start) } ?? 0
        let current = min(positions.count - 1, max(0, previous ?? startingIndex))
        let nearest = positions.indices.min { abs(positions[$0] - value) < abs(positions[$1] - value) } ?? current
        let margin = 0.08 / Double(divisions)
        let chosen = abs(positions[nearest] - value) + margin < abs(positions[current] - value)
            ? nearest : current
        previous = chosen
        return positions[chosen]
    }

    private func commitDrag() {
        if let draftRect { store.updateRect(windowID: window.id, rect: draftRect) }
        draftRect = nil
        dragStart = nil
        horizontalSnapIndex = nil
        verticalSnapIndex = nil
    }
}

struct DebugView: View {
    let store: LayoutStore

    var body: some View {
        VStack(alignment: .leading) {
            Text("Display events").font(.title2.bold())
            Text("Newest first · plug, unplug, and configuration callbacks")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.displays) { display in
                Text("\(display.name) · ID \(display.id) · \(Int(display.frame.width))×\(Int(display.frame.height)) · origin (\(Int(display.frame.minX)), \(Int(display.frame.minY)))")
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
            List(store.events) { event in
                HStack(alignment: .firstTextBaseline) {
                    Text(event.date.formatted(date: .omitted, time: .standard))
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    Text(event.message).textSelection(.enabled)
                }
            }
        }.padding()
    }
}
