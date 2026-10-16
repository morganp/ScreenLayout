import AppKit
import CoreGraphics
import Foundation

struct UnitRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init(_ frame: CGRect, in screen: CGRect) {
        x = (frame.minX - screen.minX) / screen.width
        y = (frame.minY - screen.minY) / screen.height
        width = frame.width / screen.width
        height = frame.height / screen.height
    }

    func frame(in screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + x * screen.width,
               y: screen.minY + y * screen.height,
               width: width * screen.width,
               height: height * screen.height)
    }

    mutating func clamp() {
        width = min(1, max(0.02, width))
        height = min(1, max(0.02, height))
        x = min(1 - width, max(0, x))
        y = min(1 - height, max(0, y))
    }
}

struct GridSettings: Codable, Equatable {
    var columns: Int
    var rows: Int
    var snapToGrid: Bool = true
    var preset: String = "smart"

    static func smart(for display: DisplayInfo) -> GridSettings {
        let aspect = max(0.5, display.frame.width / display.frame.height)
        return GridSettings(columns: 16, rows: min(24, max(2, Int((16 / aspect).rounded()))))
    }
}

struct DisplayInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let cgID: CGDirectDisplayID

    static func current() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
            let identifier = uuid.flatMap { CFUUIDCreateString(nil, $0) as String? }
            let bounds = CGDisplayBounds(displayID)
            return DisplayInfo(id: identifier ?? "display-\(displayID)",
                               name: screen.localizedName,
                               frame: bounds,
                               visibleFrame: bounds,
                               cgID: displayID)
        }
    }
}

struct WindowPlacement: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    var title: String
    var ordinal: Int
    var displayID: String
    var rect: UnitRect
    var spaceID: UUID? = nil
    var drawer: DrawerEdge? = nil
}

enum DrawerEdge: String, Codable, CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var title: String {
        switch self {
        case .top: "Top"
        case .topRight: "Top right"
        case .right: "Right"
        case .bottomRight: "Bottom right"
        case .bottom: "Bottom"
        case .bottomLeft: "Bottom left"
        case .left: "Left"
        case .topLeft: "Top left"
        }
    }

    var isRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var isBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
    var isLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var isTop: Bool { [.topLeft, .top, .topRight].contains(self) }

    func frame(in display: CGRect, size: DrawerSize) -> CGRect {
        let width = display.width * size.width
        let height = display.height * size.height
        let x = isRight ? display.maxX - width : (isLeft ? display.minX : display.midX - width / 2)
        let y = isBottom ? display.maxY - height : (isTop ? display.minY : display.midY - height / 2)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct DrawerSize: Codable, Hashable {
    var width: Double
    var height: Double

    static func standard(for edge: DrawerEdge) -> DrawerSize {
        switch edge {
        case .left, .right: DrawerSize(width: 1.0 / 6.0, height: 1)
        case .top, .bottom: DrawerSize(width: 1, height: 1.0 / 6.0)
        default: DrawerSize(width: 0.25, height: 0.25)
        }
    }
}

enum SpaceKind: String, Codable {
    case desktop
    case fullScreen
}

struct SpaceSlot: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var displayID: String
    var name: String
    var kind: SpaceKind = .desktop
}

struct SavedLayout: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var displaySet: String
    var mode: String
    var savedAt: Date = .now
    var windows: [WindowPlacement]
    var spaces: [SpaceSlot]? = nil
}

struct Preferences: Codable {
    var focusModesEnabled = false
    var autoRestoreOnDisplayChange = false
    var modes = ["Default", "Work", "Personal"]
    var selectedMode = "Default"
    var grids: [String: GridSettings] = [:]
    var drawers: [String: [String: DrawerSize]] = [:]
    var preferredLayouts: [String: UUID] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case focusModesEnabled, autoRestoreOnDisplayChange, modes, selectedMode, grids, drawers, preferredLayouts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusModesEnabled = try values.decodeIfPresent(Bool.self, forKey: .focusModesEnabled) ?? false
        autoRestoreOnDisplayChange = try values.decodeIfPresent(Bool.self, forKey: .autoRestoreOnDisplayChange) ?? false
        modes = try values.decodeIfPresent([String].self, forKey: .modes) ?? ["Default", "Work", "Personal"]
        selectedMode = try values.decodeIfPresent(String.self, forKey: .selectedMode) ?? "Default"
        grids = try values.decodeIfPresent([String: GridSettings].self, forKey: .grids) ?? [:]
        drawers = try values.decodeIfPresent([String: [String: DrawerSize]].self, forKey: .drawers) ?? [:]
        preferredLayouts = try values.decodeIfPresent([String: UUID].self, forKey: .preferredLayouts) ?? [:]
    }
}

struct StoredState: Codable {
    var preferences = Preferences()
    var layouts: [SavedLayout] = []
}

struct DebugEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}
