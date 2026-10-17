import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isOn: Bool { status == .enabled || status == .requiresApproval }

    static var statusText: String {
        switch status {
        case .enabled: "Launch at login: on"
        case .requiresApproval: "Launch at login: needs approval in System Settings"
        case .notFound: "Launch at login: app not found by macOS"
        default: "Launch at login: off"
        }
    }

    static func set(_ on: Bool) throws {
        if on {
            if status != .enabled { try SMAppService.mainApp.register() }
        } else if status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
