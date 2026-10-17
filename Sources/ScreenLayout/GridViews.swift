import SwiftUI

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

// One editor for a monitor's grid, used in the Layouts dock and the Drawers tab. Both read the same GridSettings.
struct GridControls: View {
    @Bindable var store: LayoutStore
    let display: DisplayInfo

    var body: some View {
        let geometry = store.gridGeometry(for: display)
        HStack(spacing: 12) {
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
                .fixedSize()
            Stepper("Columns \(geometry.columns)", value: Binding(
                get: { geometry.columns },
                set: { store.setGridDimensions(columns: $0, for: display) }), in: 2...32)
            Stepper("Rows \(geometry.rows)", value: Binding(
                get: { geometry.rows },
                set: { store.setGridDimensions(rows: $0, for: display) }), in: 2...32)
            Toggle("Snap to grid", isOn: Binding(
                get: { store.grid(for: display).snapToGrid },
                set: { store.setSnapToGrid($0, for: display) }))
            Toggle("1/2 markers", isOn: Binding(
                get: { store.grid(for: display).showHalfMarkers },
                set: { store.setMarkers(halves: $0, for: display) }))
            Toggle("1/3 markers", isOn: Binding(
                get: { store.grid(for: display).showThirdMarkers },
                set: { store.setMarkers(thirds: $0, for: display) }))
            Button("Reset grid") { store.resetGrid(for: display) }
        }
        .toggleStyle(.checkbox)
        .fixedSize()
    }
}

// Shared monitor selection for Layouts, Snap and Drawers. One display shows its name instead.
struct DisplayPicker: View {
    @Bindable var store: LayoutStore

    var body: some View {
        if store.displays.count > 1 {
            Picker("Display", selection: $store.selectedDisplayID) {
                ForEach(store.displays) { display in Text(display.name).tag(Optional(display.id)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } else if let display = store.displays.first {
            Label(display.name, systemImage: "display")
        }
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
