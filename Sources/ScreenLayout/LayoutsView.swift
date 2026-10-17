import AppKit
import SwiftUI

struct LayoutEditor: View {
    @Bindable var store: LayoutStore
    @State private var showAllApps = false
    @State private var confirmDelete = false
    @State private var showWindowSettings = false

    var body: some View {
        VStack(spacing: 0) {
            LayoutCardStrip(store: store)
            Divider()
            if let layout = store.selectedLayout, let display = store.displays.first(where: { $0.id == store.selectedDisplayID }) {
                VStack(spacing: 10) {
                    toolbarRow(layout: layout, display: display)
                    GridCanvas(store: store, layout: layout, display: display, showAllApps: showAllApps)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    dock(display: display)
                    windowBar(layout: layout, display: display)
                }
                .padding(12)
            } else {
                ContentUnavailableView {
                    Label("No layout selected", systemImage: "rectangle.on.rectangle")
                } actions: {
                    Button("New blank layout", action: store.createBlankLayout)
                    Button("Capture screen as layout", action: store.capture)
                }
            }
        }
        .onAppear { store.ensureSelectedSpace(); store.ensureSelectedWindow() }
        .onChange(of: store.selectedLayoutID) { _, _ in store.ensureSelectedSpace(); store.ensureSelectedWindow() }
        .onChange(of: store.selectedDisplayID) { _, _ in store.ensureSelectedSpace(); store.ensureSelectedWindow() }
        .onChange(of: store.selectedSpaceID) { _, _ in store.ensureSelectedWindow() }
    }

    private func toolbarRow(layout: SavedLayout, display: DisplayInfo) -> some View {
        HStack(spacing: 10) {
            DisplayPicker(store: store)
            spaceMenu(layout: layout, display: display)
            Spacer(minLength: 8)
            TextField("Layout name", text: Binding(
                get: { store.selectedLayout?.name ?? "" },
                set: { store.renameSelectedLayout($0) }))
                .frame(width: 200)
            Button("Duplicate", systemImage: "plus.square.on.square", action: store.duplicateSelectedLayout)
                .labelStyle(.iconOnly)
                .help("Duplicate layout")
            Button("Delete layout", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .labelStyle(.iconOnly)
                .help("Delete layout")
                .confirmationDialog("Delete ‘\(layout.name)’?", isPresented: $confirmDelete) {
                    Button("Delete layout", role: .destructive, action: store.deleteSelectedLayout)
                } message: {
                    Text("This removes the saved layout and its Focus assignments.")
                }
            Button("Restore", systemImage: "arrow.uturn.backward.circle", action: store.restoreSelected)
                .buttonStyle(.borderedProminent)
        }
    }

    private func spaceMenu(layout: SavedLayout, display: DisplayInfo) -> some View {
        let slots = store.spaces(for: display)
        let required = store.requiredDesktopSpaces(for: layout, display: display)
        let available = store.desktopSpaceCount(for: display)
        let missing = available.map { max(0, required - $0) }
        let ghosts = available.map { $0 > required ? Array((required + 1)...$0) : [] } ?? []
        return HStack(spacing: 8) {
            Menu {
                Picker("Space", selection: $store.selectedSpaceID) {
                    ForEach(slots) { slot in Text(slot.name).tag(Optional(slot.id)) }
                }
                .pickerStyle(.inline)
                if !ghosts.isEmpty {
                    Divider()
                    ForEach(ghosts, id: \.self) { number in
                        Button("Desktop \(number) (not in layout)") { store.addDesktops(through: number, display: display) }
                    }
                }
                Divider()
                Button("Add desktop") { store.addSpace(kind: .desktop) }
                Button("Add full screen") { store.addSpace(kind: .fullScreen) }
                Button("Move left") { store.moveSelectedSpace(-1) }
                    .disabled(store.selectedSpaceID == slots.first?.id)
                Button("Move right") { store.moveSelectedSpace(1) }
                    .disabled(store.selectedSpaceID == slots.last?.id)
                Button("Remove Space") { store.removeSelectedSpace() }
                    .disabled(!store.canRemoveSelectedSpace)
            } label: {
                Label(store.selectedSpace?.name ?? "Space", systemImage: "square.stack.3d.up")
            }
            .fixedSize()
            .onAppear { store.refreshSpaces() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
                store.refreshSpaces()
            }
            .help(store.selectedSpace?.kind == .fullScreen
                  ? "Full-screen slot: its grid position is ignored when Space application is available."
                  : "Desktop slots map to this display's existing Spaces in their shown order.")
            if let missing {
                Text(missing == 0 ? "Layout uses \(required) of \(available ?? 0) desktops" : "Layout needs \(required) desktops, \(available ?? 0) available")
                    .font(.caption)
                    .foregroundStyle(missing == 0 ? Color.secondary : Color.orange)
            } else {
                Text("Space count unavailable").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func dock(display: DisplayInfo) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                GridControls(store: store, display: display)
                Divider().frame(height: 20)
                dockApps
            }
            VStack(spacing: 8) {
                GridControls(store: store, display: display)
                dockApps
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private var dockApps: some View {
        HStack(spacing: 12) {
            Toggle("Show all apps", isOn: $showAllApps).toggleStyle(.checkbox)
            Menu("Add running app", systemImage: "plus.app") {
                ForEach(store.availableApps, id: \.id) { app in
                    Button(app.name) { store.appToAdd = app.id; store.addApp() }
                }
            }
            .fixedSize()
        }
        .fixedSize()
    }

    @ViewBuilder
    private func windowBar(layout: SavedLayout, display: DisplayInfo) -> some View {
        HStack(spacing: 10) {
            Picker("App to position", selection: $store.selectedWindowID) {
                ForEach(layout.windows.filter { $0.spaceID == store.selectedSpaceID }) { window in
                    Text("\(window.appName): \(window.title.isEmpty ? "Untitled" : window.title)").tag(Optional(window.id))
                }
            }
            .frame(maxWidth: 420)
            if let selected = store.selectedWindowID {
                Button("Window settings", systemImage: "slider.horizontal.3") { showWindowSettings = true }
                    .popover(isPresented: $showWindowSettings, arrowEdge: .top) {
                        windowSettings(layout: layout, display: display, selected: selected)
                    }
            }
            Spacer()
        }
    }

    private func windowSettings(layout: SavedLayout, display: DisplayInfo, selected: UUID) -> some View {
        let current = layout.windows.first(where: { $0.id == selected })
        let displayID = current?.displayID ?? display.id
        let rule = store.cornerRule(forDisplayID: displayID)
        let enabled = DrawerEdge.legal(for: rule).filter { store.isDrawerEnabled($0, displayID: displayID) }
        return Form {
            Picker("Window behavior", selection: Binding(
                get: { current?.drawer },
                set: { store.setDrawer($0, for: selected) })) {
                    Text("Normal").tag(DrawerEdge?.none)
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
            drawerSlotPicker(layout: layout, selected: selected)
            if let window = current, let key = store.drawerKey(for: window) {
                let sharers = store.drawerOccupants(of: key, displayID: window.displayID, excluding: selected, in: layout)
                if !sharers.isEmpty {
                    Text("Shares this slot with \(sharers.map(\.appName).joined(separator: ", ")). Only the focused one expands.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Picker("Move to Space", selection: Binding(
                get: { current?.spaceID },
                set: { if let slotID = $0 { store.moveWindowToSpace(selected, spaceID: slotID) } })) {
                    ForEach(layout.spaces ?? []) { slot in
                        Text("\(slot.name) · \(store.displays.first(where: { $0.id == slot.displayID })?.name ?? "Display")")
                            .tag(Optional(slot.id))
                    }
                }
            Picker("Move to display", selection: Binding(
                get: { current?.displayID ?? display.id },
                set: { store.moveWindow(selected, to: $0) })) {
                    ForEach(store.displays) { screen in Text(screen.name).tag(screen.id) }
                }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    // Slot choice for the selected window's drawer; shown only when its edge has several slots.
    @ViewBuilder
    private func drawerSlotPicker(layout: SavedLayout, selected: UUID) -> some View {
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
            }
        }
    }
}

private struct LayoutCardStrip: View {
    @Bindable var store: LayoutStore

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.layouts(forDisplaySet: store.displaySet)) { layout in
                    LayoutCard(store: store, layout: layout)
                }
                Menu {
                    Button("New blank layout", action: store.createBlankLayout)
                    Button("Capture screen as layout", action: store.capture)
                } label: {
                    Image(systemName: "plus").font(.title2)
                        .frame(width: 56, height: 62)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct LayoutCard: View {
    @Bindable var store: LayoutStore
    let layout: SavedLayout

    var body: some View {
        let selected = layout.id == store.selectedLayoutID
        let modes = store.assignedModes(of: layout)
        Button {
            store.selectedLayoutID = layout.id
        } label: {
            HStack(spacing: 9) {
                LayoutThumbnail(store: store, layout: layout)
                    .frame(width: 72, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name).fontWeight(.medium).lineLimit(1)
                    Text(modes.isEmpty ? "Not assigned" : modes.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .padding(8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                                              lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LayoutThumbnail: View {
    let store: LayoutStore
    let layout: SavedLayout

    var body: some View {
        Canvas { context, size in
            let shape = RoundedRectangle(cornerRadius: 3).path(in: CGRect(origin: .zero, size: size))
            context.fill(shape, with: .color(.secondary.opacity(0.1)))
            context.stroke(shape, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
            let displayID = store.selectedDisplayID ?? store.displays.first?.id
            for window in layout.windows where window.displayID == displayID {
                let rect = CGRect(x: window.rect.x * size.width, y: window.rect.y * size.height,
                                  width: window.rect.width * size.width, height: window.rect.height * size.height)
                    .insetBy(dx: 0.5, dy: 0.5)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.accentColor.opacity(0.45)))
            }
        }
    }
}
