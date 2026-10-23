import SwiftUI
import CoreGraphics
import AppKit

struct SettingsView: View {
    @Bindable var store: LayoutStore
    let controller: AppController

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Focus", systemImage: "moon") { focus }
            Tab("Access", systemImage: "lock.shield") { access }
        }
        .frame(width: 500, height: 360)
    }

    private var general: some View {
        let _ = store.loginItemTick
        return Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isOn }, set: { store.setLaunchAtLogin($0) }))
                LabeledContent("Status", value: LoginItem.statusText)
                if LoginItem.status == .requiresApproval {
                    Button("Approve in System Settings…", action: LoginItem.openSystemSettings)
                }
                Toggle("Run in background", isOn: $store.state.preferences.runInBackground)
                    .onChange(of: store.state.preferences.runInBackground) { _, _ in controller.applyActivationPolicy() }
                    .help("Closing the window hides the Dock icon and keeps ScreenLayout in the menu bar.")
            }
            Section {
                Toggle("Restore on display change", isOn: $store.state.preferences.autoRestoreOnDisplayChange)
            }
        }
        .formStyle(.grouped)
    }

    private var focus: some View {
        Form {
            Section {
                Toggle("Use macOS Focus filters", isOn: $store.state.preferences.focusModesEnabled)
                    .onChange(of: store.state.preferences.focusModesEnabled) { _, _ in store.updateFocusMonitoring() }
                if store.state.preferences.focusModesEnabled {
                    LabeledContent("Active layout profile", value: store.currentMode)
                }
            }
            Section("Focus modes") {
                LabeledContent("Found", value: "\(store.focusNames.count)")
                if store.focusCatalogError != nil {
                    Text("macOS blocks automatic listing here. Add Focus names manually.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Add Focus name", text: $store.newModeName).onSubmit { store.addMode() }
                    Button("Add", systemImage: "plus", action: store.addMode)
                        .labelStyle(.iconOnly)
                }
                Button("Refresh Focus list", action: store.refreshFocusNames)
            }
        }
        .formStyle(.grouped)
    }

    private var access: some View {
        Form {
            Section("Accessibility") {
                LabeledContent("Status", value: store.accessibilityTrusted ? "Ready" : "Not granted")
                if !store.accessibilityTrusted {
                    Button("Check Accessibility access") { store.refreshDisplays(reason: "Permission check") }
                    Button("Open Accessibility permission prompt", action: WindowAccess.requestPermission)
                }
            }
            Section("Screen Recording") {
                LabeledContent("Status", value: store.screenRecordingTrusted ? "Ready" : "Needed for inactive Spaces")
                if !store.screenRecordingTrusted {
                    Button("Request Screen Recording access", action: store.requestScreenRecording)
                    Button("Open Screen Recording settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Section("Displays and Spaces") {
                Button("Refresh displays") { store.refreshDisplays() }
                Button("Refresh Spaces", action: store.refreshSpaces)
                LabeledContent("Displays have separate Spaces", value: NSScreen.screensHaveSeparateSpaces ? "On" : "Off")
            }
        }
        .formStyle(.grouped)
    }
}
