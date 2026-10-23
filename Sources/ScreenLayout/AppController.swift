import AppKit
import CoreServices

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    var openWindowAction: (() -> Void)?
    private var closeObserver: NSObjectProtocol?

    static let launchedAtLogin: Bool = {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = LayoutStore.shared
        store.log(Self.launchedAtLogin ? "Launched at login" : "Launched")
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self?.applyActivationPolicy()
            }
        }
        if Self.launchedAtLogin { applyActivationPolicy() }
        SnapController.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        let store = LayoutStore.shared
        store.refreshAccessibility()
        store.refreshScreenRecording()
        store.refreshFocusNames()
        store.refreshSpaces()
        store.refreshLoginItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        showMainWindow()
        return false
    }

    private var hasVisibleWindow: Bool {
        NSApp.windows.contains { ($0.isVisible || $0.isMiniaturized) && !($0 is NSPanel) && $0.canBecomeMain }
    }

    func applyActivationPolicy() {
        let hide = LayoutStore.shared.state.preferences.runInBackground && !hasVisibleWindow
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate()
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                self?.openWindowAction?()
            }
        }
    }
}
