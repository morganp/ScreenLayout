import SwiftUI

struct FooterBar: View {
    let store: LayoutStore
    @Binding var showEventLog: Bool

    var body: some View {
        HStack(spacing: 14) {
            Label("Watching displays", systemImage: "circle.fill")
                .labelStyle(WatchingLabelStyle())
            Text(store.displays.count == 1 ? "1 display" : "\(store.displays.count) displays")
            Text(store.status).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if store.accessibilityTrusted {
                Label("Accessibility ready", systemImage: "checkmark.shield")
            } else {
                Label("Accessibility needed", systemImage: "exclamationmark.shield")
                    .foregroundStyle(.orange)
            }
            Button("Event log", systemImage: "list.bullet.rectangle") { showEventLog = true }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct WatchingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(.green)
            configuration.title
        }
    }
}

struct EventLogView: View {
    let store: LayoutStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Event log").font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ForEach(store.displays) { display in
                Text("\(display.name) · ID \(display.id) · \(Int(display.frame.width))×\(Int(display.frame.height)) · origin (\(Int(display.frame.minX)), \(Int(display.frame.minY)))")
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
            List(store.events) { event in
                HStack(alignment: .firstTextBaseline) {
                    Text(event.date.formatted(date: .omitted, time: .standard))
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    Text(event.message).textSelection(.enabled)
                }
            }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 440)
    }
}
