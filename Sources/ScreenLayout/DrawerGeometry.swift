import CoreGraphics

// How a monitor's corners are shared between drawers. Stored per monitor in Preferences.
enum CornerRule: String, Codable, CaseIterable {
    case separate
    case topBottom
    case leftRight

    var title: String {
        switch self {
        case .separate: "Separate corners"
        case .topBottom: "Top and bottom"
        case .leftRight: "Left and right"
        }
    }

    var summary: String {
        switch self {
        case .separate: "Corner drawers take the corners; the four edge drawers fit between them."
        case .topBottom: "Top and bottom drawers span the full width; left and right fit between them. No corner drawers."
        case .leftRight: "Left and right drawers span the full height; top and bottom fit between them. No corner drawers."
        }
    }
}

extension DrawerEdge {
    var isCorner: Bool { (isLeft || isRight) && (isTop || isBottom) }
    // Left and right strips measure their depth as width; top and bottom as height; corners use both.
    var hasHorizontalDepth: Bool { isLeft || isRight }
    var hasVerticalDepth: Bool { isTop || isBottom }

    func isLegal(for rule: CornerRule) -> Bool { !isCorner || rule == .separate }

    static func legal(for rule: CornerRule) -> [DrawerEdge] {
        [.topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight].filter { $0.isLegal(for: rule) }
    }

    // The edge a drawer really uses under a rule. A corner drawer maps to the edge the rule keeps.
    func resolved(for rule: CornerRule) -> DrawerEdge {
        guard isCorner else { return self }
        switch rule {
        case .separate: return self
        case .topBottom: return isTop ? .top : .bottom
        case .leftRight: return isLeft ? .left : .right
        }
    }
}

// One drawer: a position and a slot along it. Corners only have slot 0.
struct DrawerKey: Hashable {
    var edge: DrawerEdge
    var slot: Int = 0
}

// The one definition of where each drawer rests. The Drawers preview, restore, live resizing and
// WindowAccess.setDrawerFrame all take their rectangles from here.
enum DrawerGeometry {
    static let maxSlots = 8

    // Splits [low, low + length] into equal slots. With `cells` (grid cells along the axis, snap on),
    // inner boundaries move to the nearest cell boundary, every slot keeps at least one cell and
    // boundaries stay strictly increasing; the count is capped at the cell count.
    static func divide(low: Double, length: Double, count: Int, cells: Int?) -> [(start: Double, end: Double)] {
        var slots = min(maxSlots, max(1, count))
        let high = low + length
        var first = 0
        var last = 0
        if let cells {
            first = Int((low * Double(cells)).rounded())
            last = Int((high * Double(cells)).rounded())
            slots = min(slots, max(1, last - first))
        }
        var cuts = (1..<max(slots, 1)).map { low + length * Double($0) / Double(slots) }
        if let cells {
            var previous = first
            for index in cuts.indices {
                let lower = previous + 1
                let upper = last - (slots - 1 - index)
                previous = min(upper, max(lower, Int((cuts[index] * Double(cells)).rounded())))
                cuts[index] = Double(previous) / Double(cells)
            }
        }
        let bounds = [low] + cuts + [high]
        return (0..<slots).map { (bounds[$0], bounds[$0 + 1]) }
    }

    static let defaultCornerCount = 0

    static func defaultCount(for edge: DrawerEdge) -> Int { edge.isCorner ? defaultCornerCount : 1 }

    // `configured` holds the sizes the user set; any other position uses its standard size. `counts` is
    // the drawer count per position: edges 0 to 8 (default 1), corners 0 or 1 (default off). A drawer
    // with count 0, or illegal under the rule, has no rectangle and reserves no space; every enabled
    // drawer reserves space for its neighbours at its effective depth (saved size, else standard).
    // With `grid` set (snap on), slot boundaries snap to its cells. Returns a rectangle for every
    // enabled drawer, inside `area`.
    static func rects(in area: CGRect, configured: [DrawerEdge: DrawerSize], rule: CornerRule,
                      counts: [DrawerEdge: Int] = [:], grid: GridGeometry? = nil) -> [DrawerKey: CGRect] {
        func size(_ edge: DrawerEdge) -> DrawerSize { configured[edge] ?? .standard(for: edge) }
        func enabled(_ edge: DrawerEdge) -> Bool { edge.isLegal(for: rule) && (counts[edge] ?? defaultCount(for: edge)) > 0 }
        func depth(_ edge: DrawerEdge, horizontal: Bool) -> Double {
            guard enabled(edge) else { return 0 }
            return min(1, horizontal ? size(edge).width : size(edge).height)
        }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        var result: [DrawerKey: CGRect] = [:]

        func addSlots(_ edge: DrawerEdge, _ rect: CGRect) {
            guard enabled(edge) else { return }
            let alongY = edge.hasHorizontalDepth
            let parts = divide(low: alongY ? rect.minY : rect.minX, length: alongY ? rect.height : rect.width,
                               count: counts[edge] ?? defaultCount(for: edge), cells: alongY ? grid?.rows : grid?.columns)
            for (slot, part) in parts.enumerated() {
                result[DrawerKey(edge: edge, slot: slot)] = alongY
                    ? CGRect(x: rect.minX, y: part.start, width: rect.width, height: part.end - part.start)
                    : CGRect(x: part.start, y: rect.minY, width: part.end - part.start, height: rect.height)
            }
        }

        func edgeRect(_ edge: DrawerEdge, from start: Double, to end: Double) -> CGRect {
            let low = min(start, 0.98)
            let span = max(0.02, min(1, end) - low)
            let value = size(edge)
            if edge.hasHorizontalDepth {
                let width = min(1, value.width)
                let along = min(value.height, span)
                return CGRect(x: edge == .left ? 0 : 1 - width, y: low + (span - along) / 2, width: width, height: along)
            }
            let height = min(1, value.height)
            let along = min(value.width, span)
            return CGRect(x: low + (span - along) / 2, y: edge == .top ? 0 : 1 - height, width: along, height: height)
        }

        switch rule {
        case .separate:
            for corner in DrawerEdge.allCases where corner.isCorner && enabled(corner) {
                result[DrawerKey(edge: corner)] = corner.frame(in: unit, size: size(corner))
            }
            // Top and bottom run between enabled corners and otherwise the full width. Left and right
            // run between each corner, or below and above an enabled top or bottom drawer.
            func vertical(_ corner: DrawerEdge, _ horizontalEdge: DrawerEdge) -> Double {
                enabled(corner) ? depth(corner, horizontal: false) : depth(horizontalEdge, horizontal: false)
            }
            addSlots(.top, edgeRect(.top, from: depth(.topLeft, horizontal: true), to: 1 - depth(.topRight, horizontal: true)))
            addSlots(.bottom, edgeRect(.bottom, from: depth(.bottomLeft, horizontal: true), to: 1 - depth(.bottomRight, horizontal: true)))
            addSlots(.left, edgeRect(.left, from: vertical(.topLeft, .top), to: 1 - vertical(.bottomLeft, .bottom)))
            addSlots(.right, edgeRect(.right, from: vertical(.topRight, .top), to: 1 - vertical(.bottomRight, .bottom)))
        case .topBottom:
            addSlots(.top, edgeRect(.top, from: 0, to: 1))
            addSlots(.bottom, edgeRect(.bottom, from: 0, to: 1))
            addSlots(.left, edgeRect(.left, from: depth(.top, horizontal: false), to: 1 - depth(.bottom, horizontal: false)))
            addSlots(.right, edgeRect(.right, from: depth(.top, horizontal: false), to: 1 - depth(.bottom, horizontal: false)))
        case .leftRight:
            addSlots(.left, edgeRect(.left, from: 0, to: 1))
            addSlots(.right, edgeRect(.right, from: 0, to: 1))
            addSlots(.top, edgeRect(.top, from: depth(.left, horizontal: true), to: 1 - depth(.right, horizontal: true)))
            addSlots(.bottom, edgeRect(.bottom, from: depth(.left, horizontal: true), to: 1 - depth(.right, horizontal: true)))
        }
        return result.mapValues { rect in
            CGRect(x: area.minX + rect.minX * area.width, y: area.minY + rect.minY * area.height,
                   width: rect.width * area.width, height: rect.height * area.height)
        }
    }
}
