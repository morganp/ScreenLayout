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
    @Binding var tab: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Snap windows").font(.title2.bold())
            Text("Press the overlay shortcut, drag across grid cells, and release to snap the window. Escape or releasing outside the grid cancels.")
                .foregroundStyle(.secondary)
            ShortcutRecorder(title: "Show overlay", key: store.state.preferences.snapHotkey) {
                store.state.preferences.snapHotkey = $0
            }
            .frame(maxWidth: 360)
            ShortcutRecorder(title: "Undo or redo last snap", key: store.state.preferences.undoHotkey) {
                store.state.preferences.undoHotkey = $0
            }
            .frame(maxWidth: 360)
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
            Stepper("Gap between windows: \(Int(store.state.preferences.snapGap)) pt",
                    value: $store.state.preferences.snapGap, in: 0...64, step: 1)
                .frame(maxWidth: 360)
            Picker("Window to snap", selection: $store.state.preferences.snapTarget) {
                ForEach(SnapTarget.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 360)
            Toggle("Record snaps into the selected layout", isOn: $store.state.preferences.recordSnaps)
            Text("When on, a snap updates the matching window in the selected layout (without the gap). Windows that are not in the layout are left alone. Use the menu bar action to add a window.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Grid").font(.headline)
            Text("The overlay uses the same grid as the Layouts editor for each monitor. Changes here and there are one setting.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Monitor", selection: $store.selectedDisplayID) {
                ForEach(store.displays) { display in Text(display.name).tag(Optional(display.id)) }
            }
            .frame(maxWidth: 400)
            if let display = store.displays.first(where: { $0.id == store.selectedDisplayID }) {
                GridControls(store: store, display: display)
            }
            Button("Open in Layouts editor") { tab = 0 }
            Spacer()
        }
        .padding()
    }
}
