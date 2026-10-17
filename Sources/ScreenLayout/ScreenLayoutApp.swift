import AppKit
import SwiftUI

@main struct ScreenLayoutApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller
    private let store = LayoutStore.shared

    var body: some Scene {
        WindowGroup("ScreenLayout", id: "main") {
            ContentView(store: store, controller: controller)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(AppController.launchedAtLogin ? .suppressed : .presented)

        MenuBarExtra {
            MenuBarContent(store: store, controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(store: store, controller: controller)
        }
    }
}

struct MenuBarLabel: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "rectangle.3.group")
            .task { controller.openWindowAction = { openWindow(id: "main") } }
    }
}

struct MenuBarContent: View {
    @Bindable var store: LayoutStore
    let controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let _ = store.loginItemTick
        Text(store.status)
        Text(LoginItem.statusText)
        Divider()
        Button("Restore selected layout", action: store.restoreSelected)
            .disabled(store.selectedLayout == nil)
        Button("Restore matching layout for current displays", action: store.restoreLatest)
        Button("Snap window…") { SnapController.shared.showAfterMenu() }
        Button("Capture focused window into selected layout") { SnapController.shared.captureFocusedWindowAfterMenu() }
            .disabled(store.selectedLayout == nil)
        Button("Open ScreenLayout") {
            controller.openWindowAction = { openWindow(id: "main") }
            controller.showMainWindow()
        }
        Divider()
        Toggle("Launch at login", isOn: Binding(
            get: { LoginItem.isOn }, set: { store.setLaunchAtLogin($0) }))
        if LoginItem.status == .requiresApproval {
            Button("Approve in System Settings…", action: LoginItem.openSystemSettings)
        }
        Toggle("Run in background", isOn: Binding(
            get: { store.state.preferences.runInBackground },
            set: { store.state.preferences.runInBackground = $0; controller.applyActivationPolicy() }))
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit ScreenLayout") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case automation, layouts, snap, drawers

    var id: Self { self }
    var title: String {
        switch self {
        case .automation: "Automation"
        case .layouts: "Layouts"
        case .snap: "Snap"
        case .drawers: "Drawers"
        }
    }
}

struct ContentView: View {
    @Bindable var store: LayoutStore
    let controller: AppController
    @State private var tab = PanelTab.automation
    @State private var showEventLog = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .automation: AutomationView(store: store, tab: $tab)
                case .layouts: LayoutEditor(store: store)
                case .snap: SnapSettings(store: store, tab: $tab)
                case .drawers: DrawerEditor(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FooterBar(store: store, showEventLog: $showEventLog)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(PanelTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 380)
            }
        }
        .sheet(isPresented: $showEventLog) { EventLogView(store: store) }
    }
}
