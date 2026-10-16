import SwiftUI

@main struct ScreenLayoutApp: App {
    @State private var store = LayoutStore()

    var body: some Scene {
        WindowGroup("ScreenLayout") {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 680)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.refreshAccessibility()
                    store.refreshFocusNames()
                    store.refreshSpaces()
                }
        }
        .defaultSize(width: 1180, height: 760)
    }
}

struct ContentView: View {
    @Bindable var store: LayoutStore
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
                    Text("Debug events").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .padding()
                Divider()
                if tab == 0 { LayoutEditor(store: store) }
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
                    Stepper("Columns: \(store.grid(for: display).columns)", value: Binding(
                        get: { store.grid(for: display).columns },
                        set: { store.setGridDimensions(columns: $0, for: display) }), in: 2...32)
                    Stepper("Rows: \(store.grid(for: display).rows)", value: Binding(
                        get: { store.grid(for: display).rows },
                        set: { store.setGridDimensions(rows: $0, for: display) }), in: 2...32)
                    Toggle("Snap to grid", isOn: Binding(
                        get: { store.grid(for: display).snapToGrid },
                        set: { store.setSnapToGrid($0, for: display) }))
                        .fixedSize()
                    Button("Reset grid") { store.resetGrid(for: display) }
                }
                .font(.subheadline)
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
                Canvas { context, size in
                    let grid = store.grid(for: display)
                    var path = Path()
                    for column in 0...grid.columns {
                        let x = size.width * CGFloat(column) / CGFloat(grid.columns)
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for row in 0...grid.rows {
                        let y = size.height * CGFloat(row) / CGFloat(grid.rows)
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                }
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
        if grid.snapToGrid {
            if abs(translation.width) > 2 {
                next.x = snappedMoveOrigin(next.x, start: start.x, size: start.width,
                                           divisions: grid.columns, previous: &horizontalSnapIndex)
            }
            if abs(translation.height) > 2 {
                next.y = snappedMoveOrigin(next.y, start: start.y, size: start.height,
                                           divisions: grid.rows, previous: &verticalSnapIndex)
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
        if grid.snapToGrid {
            if abs(translation.width) > 2 {
                if horizontalSnapIndex == nil { horizontalSnapIndex = Int(((start.x + start.width) * Double(grid.columns)).rounded()) }
                let right = hystereticCell(next.x + next.width, previous: &horizontalSnapIndex,
                                           divisions: grid.columns, allowed: 1...grid.columns)
                next.width = max(1 / Double(grid.columns), Double(right) / Double(grid.columns) - next.x)
            }
            if abs(translation.height) > 2 {
                if verticalSnapIndex == nil { verticalSnapIndex = Int(((start.y + start.height) * Double(grid.rows)).rounded()) }
                let bottom = hystereticCell(next.y + next.height, previous: &verticalSnapIndex,
                                            divisions: grid.rows, allowed: 1...grid.rows)
                next.height = max(1 / Double(grid.rows), Double(bottom) / Double(grid.rows) - next.y)
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
