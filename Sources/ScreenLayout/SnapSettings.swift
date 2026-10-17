import AppKit
import SwiftUI

@MainActor @Observable final class ShortcutRecording {
    var active = false
    private var monitor: Any?

    func start(onKey: @escaping @MainActor @Sendable (HotKey) -> Void) {
        stop()
        active = true
        SnapController.shared.suspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = HotKey(event: event)
            MainActor.assumeIsolated {
                self?.stop()
                if let key { onKey(key) }
                SnapController.shared.registerHotkeys()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        active = false
    }
}

struct ShortcutRecorder: View {
    let title: String
    let key: HotKey
    let onChange: @MainActor @Sendable (HotKey) -> Void
    @State private var recording = ShortcutRecording()

    var body: some View {
        LabeledContent(title) {
            Button(recording.active ? "Type shortcut…" : key.label) {
                if recording.active {
                    recording.stop()
                    SnapController.shared.registerHotkeys()
                } else {
                    recording.start(onKey: onChange)
                }
            }
            .frame(minWidth: 120)
        }
    }
}

struct SnapSettings: View {
    @Bindable var store: LayoutStore
    @Binding var tab: PanelTab

    var body: some View {
        Form {
            Section("Shortcuts") {
                ShortcutRecorder(title: "Show overlay", key: store.state.preferences.snapHotkey) {
                    store.state.preferences.snapHotkey = $0
                }
                ShortcutRecorder(title: "Undo or redo last snap", key: store.state.preferences.undoHotkey) {
                    store.state.preferences.undoHotkey = $0
                }
                HStack {
                    Button("Reset shortcuts") {
                        store.state.preferences.snapHotkey = .defaultSnap
                        store.state.preferences.undoHotkey = .defaultUndo
                        SnapController.shared.registerHotkeys()
                    }
                    if let error = store.snapHotkeyError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                    }
                }
            }
            Section("Snapping") {
                Stepper("Gap between windows: \(Int(store.state.preferences.snapGap)) pt",
                        value: $store.state.preferences.snapGap, in: 0...64, step: 1)
                Picker("Window to snap", selection: $store.state.preferences.snapTarget) {
                    ForEach(SnapTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Record snaps into the selected layout", isOn: $store.state.preferences.recordSnaps)
                    .help("A snap updates the matching window in the selected layout, without the gap.")
            }
            Section("Grid") {
                LabeledContent("Display") { DisplayPicker(store: store) }
                if let display = store.displays.first(where: { $0.id == store.selectedDisplayID }) {
                    let geometry = store.gridGeometry(for: display)
                    let setting = store.grid(for: display)
                    LabeledContent("Grid", value: "\(geometry.columns) × \(geometry.rows)")
                    LabeledContent("Snap to grid", value: setting.snapToGrid ? "On" : "Off")
                    LabeledContent("Markers", value: markerSummary(setting))
                }
                Button("Edit grid in Layouts") { tab = .layouts }
            }
        }
        .formStyle(.grouped)
    }

    private func markerSummary(_ setting: GridSettings) -> String {
        let markers = [setting.showHalfMarkers ? "1/2" : nil, setting.showThirdMarkers ? "1/3" : nil].compactMap { $0 }
        return markers.isEmpty ? "None" : markers.joined(separator: ", ")
    }
}
