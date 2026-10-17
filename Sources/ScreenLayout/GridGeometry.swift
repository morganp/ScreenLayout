import CoreGraphics

struct GridSelection: Equatable {
    var columns: ClosedRange<Int>
    var rows: ClosedRange<Int>
}

// The single definition of a monitor's grid, used by the Layouts editor canvas and the snap overlay.
// It resolves a display's GridSettings to effective columns and rows and owns the cell-rect math.
// All rectangles are in the display's Core Graphics space (origin top left), the same space as
// DisplayInfo.visibleFrame and Accessibility window frames.
struct GridGeometry: Equatable {
    let columns: Int
    let rows: Int

    init(columns: Int, rows: Int) {
        self.columns = min(64, max(1, columns))
        self.rows = min(64, max(1, rows))
    }

    init(_ settings: GridSettings, display: DisplayInfo) {
        if settings.preset == "smart" {
            let smart = GridSettings.smart(for: display)
            self.init(columns: smart.columns, rows: smart.rows)
        } else {
            self.init(columns: settings.columns, rows: settings.rows)
        }
    }

    func unitRect(for selection: GridSelection) -> UnitRect {
        UnitRect(x: Double(selection.columns.lowerBound) / Double(columns),
                 y: Double(selection.rows.lowerBound) / Double(rows),
                 width: Double(selection.columns.count) / Double(columns),
                 height: Double(selection.rows.count) / Double(rows))
    }

    func frame(for selection: GridSelection, in area: CGRect) -> CGRect {
        unitRect(for: selection).frame(in: area)
    }

    func cellRect(column: Int, row: Int, in area: CGRect) -> CGRect {
        frame(for: GridSelection(columns: column...column, rows: row...row), in: area)
    }

    // Guide positions as unit fractions of the display, drawn on both axes. They are visual only and
    // need not fall on a cell boundary.
    static func markerFractions(halves: Bool, thirds: Bool) -> [Double] {
        var fractions: [Double] = []
        if thirds { fractions.append(1.0 / 3.0) }
        if halves { fractions.append(0.5) }
        if thirds { fractions.append(2.0 / 3.0) }
        return fractions
    }

    // Point in a top-left-origin area of the given size; clamps to the nearest cell.
    func cell(at point: CGPoint, in area: CGRect) -> (column: Int, row: Int) {
        let column = Int(((point.x - area.minX) / area.width * CGFloat(columns)).rounded(.down))
        let row = Int(((point.y - area.minY) / area.height * CGFloat(rows)).rounded(.down))
        return (min(max(column, 0), columns - 1), min(max(row, 0), rows - 1))
    }
}
