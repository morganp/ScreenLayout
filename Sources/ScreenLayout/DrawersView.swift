import SwiftUI

struct DrawerEditor: View {
    @Bindable var store: LayoutStore
    @State private var selectedEdge: DrawerEdge = .right
    @State private var selectedSlot = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let display = store.displays.first(where: { $0.id == store.selectedDisplayID }) {
                let rule = store.cornerRule(for: display)
                let edge = selectedEdge.resolved(for: rule)
                let requested = store.drawerCount(for: edge, display: display)
                let slots = store.effectiveDrawerCount(for: edge, display: display)
                let slot = max(0, min(selectedSlot, slots - 1))
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        DisplayPicker(store: store)
                        Picker("Corners", selection: Binding(
                            get: { rule },
                            set: { store.setCornerRule($0, for: display) })) {
                                ForEach(CornerRule.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .help(rule.summary)
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
                                Text("The grid has room for \(slots) here.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Text(requested == 0 ? "Off"
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
