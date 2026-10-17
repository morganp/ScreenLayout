import SwiftUI

struct AutomationView: View {
    @Bindable var store: LayoutStore
    @Binding var tab: PanelTab

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RightNowBanner(store: store)
                    AutomationMatrix(store: store, tab: $tab)
                    HStack {
                        Button("Capture screen as layout", systemImage: "camera.viewfinder") {
                            let before = store.state.layouts.count
                            store.capture()
                            if store.state.layouts.count > before { tab = .layouts }
                        }
                        Button("New blank layout", systemImage: "plus.rectangle") {
                            store.createBlankLayout()
                            tab = .layouts
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            WatchingCard(store: store)
                .frame(width: 250)
        }
        .padding()
    }
}

private struct RightNowBanner: View {
    let store: LayoutStore

    var body: some View {
        let layout = store.appliedLayout
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Right now").font(.headline)
                Text(store.displayNames(forDisplaySet: store.displaySet).joined(separator: " + "))
                    .lineLimit(1)
                Text(store.state.preferences.focusModesEnabled ? "Focus: \(store.currentMode)" : "Focus filters off")
                    .foregroundStyle(.secondary)
                Text(layout.map { "Applies: \($0.name)" } ?? "No layout applies")
                    .foregroundStyle(layout == nil ? .orange : .primary)
                    .fontWeight(.medium)
            }
            Spacer()
            Button("Restore now", action: store.restoreLatest)
                .buttonStyle(.borderedProminent)
                .disabled(layout == nil)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.6)))
    }
}

private struct AutomationMatrix: View {
    @Bindable var store: LayoutStore
    @Binding var tab: PanelTab

    var body: some View {
        let modes = store.selectableFocusNames
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    header("Monitors").frame(width: 190, alignment: .leading)
                    ForEach(modes, id: \.self) { mode in
                        header(mode).frame(width: 170, alignment: .leading)
                    }
                }
                ForEach(store.monitorSets, id: \.self) { set in
                    Divider().gridCellUnsizedAxes(.horizontal).gridCellColumns(modes.count + 1)
                    GridRow {
                        rowHeader(set).frame(width: 190, alignment: .leading)
                        ForEach(modes, id: \.self) { mode in
                            MatrixCell(store: store, tab: $tab, set: set, mode: mode, modes: modes)
                                .frame(width: 170, alignment: .leading)
                        }
                    }
                }
            }
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func rowHeader(_ set: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(store.displayNames(forDisplaySet: set).enumerated()), id: \.offset) { _, name in
                Text(name).lineLimit(1)
            }
            Text(set == store.displaySet ? "Connected" : "Not connected")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

private struct MatrixCell: View {
    @Bindable var store: LayoutStore
    @Binding var tab: PanelTab
    let set: String
    let mode: String
    let modes: [String]

    var body: some View {
        let layouts = store.layouts(forDisplaySet: set)
        let assigned = store.assignedLayoutID(mode: mode, displaySet: set)
        let layout = layouts.first { $0.id == assigned }
        let isLive = set == store.displaySet && mode == store.currentMode
        HStack(spacing: 4) {
            if layouts.isEmpty {
                Text("No layout saved").font(.callout).foregroundStyle(.orange)
            } else {
                Menu {
                    ForEach(layouts) { candidate in
                        Button {
                            store.assign(candidate, mode: mode, displaySet: set)
                        } label: {
                            if candidate.id == assigned { Label(candidate.name, systemImage: "checkmark") }
                            else { Text(candidate.name) }
                        }
                    }
                    Divider()
                    Button("None") { store.assign(nil, mode: mode, displaySet: set) }
                    if mode != "Default" {
                        let fallback = store.assignedLayoutID(mode: "Default", displaySet: set)
                            .flatMap { id in layouts.first { $0.id == id } }
                        Button("Same as Default") { store.assign(fallback, mode: mode, displaySet: set) }
                            .disabled(fallback == nil)
                    }
                    if let layout, set == store.displaySet {
                        Divider()
                        Button("Edit \(layout.name)") { edit(layout) }
                    }
                } label: {
                    Text(layout?.name ?? "None")
                        .lineLimit(1)
                        .foregroundStyle(layout == nil ? .secondary : .primary)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                if let layout, set == store.displaySet {
                    Button("Edit \(layout.name)", systemImage: "pencil") { edit(layout) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isLive ? Color.accentColor.opacity(0.15) : .clear)
        .overlay { if isLive { Rectangle().stroke(Color.accentColor, lineWidth: 2) } }
    }

    private func edit(_ layout: SavedLayout) {
        store.selectedLayoutID = layout.id
        tab = .layouts
    }
}

private struct WatchingCard: View {
    let store: LayoutStore

    var body: some View {
        let prefs = store.state.preferences
        GroupBox("Watching") {
            VStack(alignment: .leading, spacing: 10) {
                row("Display changes", prefs.autoRestoreOnDisplayChange ? "Restore layout" : "Log only")
                row("Focus filter", prefs.focusModesEnabled ? "On" : "Off")
                row("Active drawers", store.activeDrawerCount == 0 ? "None" : "\(store.activeDrawerCount)")
                Divider()
                Text("Displays").font(.subheadline.weight(.semibold))
                ForEach(store.displays) { display in
                    VStack(alignment: .leading, spacing: 1) {
                        Label(display.name, systemImage: "display").lineLimit(1)
                        Text("\(Int(display.frame.width)) × \(Int(display.frame.height))")
                            .font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
