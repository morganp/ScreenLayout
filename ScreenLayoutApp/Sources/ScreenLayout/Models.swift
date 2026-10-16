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
    var preferredLayouts: [String: UUID] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case focusModesEnabled, autoRestoreOnDisplayChange, modes, selectedMode, grids, preferredLayouts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusModesEnabled = try values.decodeIfPresent(Bool.self, forKey: .focusModesEnabled) ?? false
        autoRestoreOnDisplayChange = try values.decodeIfPresent(Bool.self, forKey: .autoRestoreOnDisplayChange) ?? false
        modes = try values.decodeIfPresent([String].self, forKey: .modes) ?? ["Default", "Work", "Personal"]
        selectedMode = try values.decodeIfPresent(String.self, forKey: .selectedMode) ?? "Default"
        grids = try values.decodeIfPresent([String: GridSettings].self, forKey: .grids) ?? [:]
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
