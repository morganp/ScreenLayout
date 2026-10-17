// Portions adapted from GridSnap (https://github.com/konieczkow/gridsnap),
// Copyright (c) 2026 Maciej Gajewski, MIT License. See THIRD_PARTY_NOTICES.md.

import AppKit
import Carbon

final class SnapPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// Draws the shared grid for one display and reports drag selections.
// The view is flipped so cell rows run top to bottom, matching GridGeometry and UnitRect.
final class SnapGridView: NSView {
    var geometry = GridGeometry(columns: 2, rows: 2) { didSet { needsDisplay = true } }
    var markerFractions: [Double] = [] { didSet { needsDisplay = true } }
    var onChange: ((GridSelection?) -> Void)?
    var onCommit: ((GridSelection?) -> Void)?
    var onCancel: (() -> Void)?
    private var start: (column: Int, row: Int)?
    private var end: (column: Int, row: Int)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var gridRect: CGRect { bounds.insetBy(dx: 10, dy: 10) }

    var selection: GridSelection? {
        guard let start, let end else { return nil }
        return GridSelection(columns: min(start.column, end.column)...max(start.column, end.column),
                             rows: min(start.row, end.row)...max(start.row, end.row))
    }

    func reset() { start = nil; end = nil; needsDisplay = true }

    private func cell(for event: NSEvent) -> (column: Int, row: Int)? {
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point) ? geometry.cell(at: point, in: gridRect) : nil
    }

    override func mouseDown(with event: NSEvent) {
        start = cell(for: event)
        end = start
        needsDisplay = true
    }

    private func track(_ event: NSEvent) {
        let next = cell(for: event)
        guard next?.column != end?.column || next?.row != end?.row else { return }
        end = next
        needsDisplay = true
        onChange?(selection)
    }

    override func mouseDragged(with event: NSEvent) { track(event) }

    override func mouseUp(with event: NSEvent) {
        track(event)
        onCommit?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let area = gridRect
        guard !area.isEmpty else { return }
        for column in 0..<geometry.columns {
            for row in 0..<geometry.rows {
                let path = NSBezierPath(roundedRect: geometry.cellRect(column: column, row: row, in: area).insetBy(dx: 1, dy: 1),
                                        xRadius: 3, yRadius: 3)
                NSColor.white.withAlphaComponent(0.10).setFill(); path.fill()
                NSColor.white.withAlphaComponent(0.20).setStroke(); path.stroke()
            }
        }
        if !markerFractions.isEmpty {
            let markers = NSBezierPath()
            for fraction in markerFractions {
                let x = area.minX + area.width * fraction
                let y = area.minY + area.height * fraction
                markers.move(to: CGPoint(x: x, y: area.minY)); markers.line(to: CGPoint(x: x, y: area.maxY))
                markers.move(to: CGPoint(x: area.minX, y: y)); markers.line(to: CGPoint(x: area.maxX, y: y))
            }
            markers.lineWidth = 2
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
            markers.stroke()
        }
        if let selection {
            let path = NSBezierPath(roundedRect: geometry.frame(for: selection, in: area).insetBy(dx: 1, dy: 1),
                                    xRadius: 4, yRadius: 4)
            NSColor.controlAccentColor.withAlphaComponent(0.85).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.7).setStroke(); path.lineWidth = 1.5; path.stroke()
        }
    }
}

@MainActor final class SnapController {
    static let shared = SnapController()

    private struct SnapRecord {
        let window: AXUIElement
        let before: CGRect
        let after: CGRect
        var undone = false
    }

    private enum HotkeyID {
        static let overlay: UInt32 = 1
        static let undo: UInt32 = 2
    }

    private let store = LayoutStore.shared
    private let panel: SnapPanel
    private let gridView = SnapGridView()
    private var history: [SnapRecord] = []
    private var monitors: [Any] = []
    private var target: AXUIElement?
    private var original: CGRect?
    private var display: DisplayInfo?
    private var geometry = GridGeometry(columns: 2, rows: 2)
    private var lastApplied: GridSelection?

    var isVisible: Bool { panel.isVisible }

    private init() {
        panel = SnapPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        gridView.autoresizingMask = [.width, .height]
        background.addSubview(gridView)
        panel.contentView = background
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        gridView.onChange = { [weak self] selection in self?.apply(selection) }
        gridView.onCommit = { [weak self] selection in self?.commit(selection) }
        gridView.onCancel = { [weak self] in self?.cancel() }
    }

    func start() {
        HotkeyCenter.shared.onPress = { [weak self] id in
            guard let self else { return }
            if id == HotkeyID.overlay { toggle() } else if id == HotkeyID.undo { undoOrRedo() }
        }
        registerHotkeys()
    }

    func suspendHotkeys() { HotkeyCenter.shared.unregisterAll() }

    func registerHotkeys() {
        let center = HotkeyCenter.shared
        center.unregisterAll()
        let preferences = store.state.preferences
        var failures: [String] = []
        for (id, key, name) in [(HotkeyID.overlay, preferences.snapHotkey, "Snap overlay"),
                                (HotkeyID.undo, preferences.undoHotkey, "Undo snap")] {
            let status = center.register(key, id: id)
            if status == noErr {
                store.log("\(name) shortcut registered: \(key.label)")
            } else {
                let reason = status == OSStatus(eventHotKeyExistsErr) ? "already in use" : "error \(status)"
                failures.append("\(name) shortcut \(key.label) unavailable (\(reason))")
            }
        }
        store.snapHotkeyError = failures.isEmpty ? nil : failures.joined(separator: "; ")
        if let error = store.snapHotkeyError {
            store.status = error
            store.log(error)
        }
    }

    func toggle() {
        if panel.isVisible { cancel() } else { show() }
    }

    // Grid cells come from display.visibleFrame, the same rectangle the Layouts editor uses. It is in
    // Core Graphics space (top left origin), which is also the Accessibility space, so snapped frames
    // need no flip. Only the cursor position and the overlay panel placement use AppKit space.
    func show() {
        guard WindowAccess.trusted else {
            WindowAccess.requestPermission()
            store.status = "Accessibility is not trusted for this build"
            store.log(store.status)
            return
        }
        if store.displays.isEmpty { store.refreshDisplays() }
        let mouse = NSEvent.mouseLocation
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let cursor = CGPoint(x: mouse.x, y: primaryTop - mouse.y)
        guard let display = store.displays.first(where: { $0.frame.contains(cursor) }) ?? store.displays.first else { return }
        // Capture the target before the panel exists so focus has not moved.
        let picked = (store.state.preferences.snapTarget == .underCursor ? WindowAccess.windowUnderCursor(at: cursor) : nil)
            ?? WindowAccess.focusedWindow()
        guard let window = picked, let frame = WindowAccess.frame(of: window) else {
            store.status = "No window to snap"
            store.log(store.status)
            return
        }
        target = window
        original = frame
        self.display = display
        lastApplied = nil
        geometry = store.gridGeometry(for: display)
        gridView.geometry = geometry
        let setting = store.grid(for: display)
        gridView.markerFractions = GridGeometry.markerFractions(halves: setting.showHalfMarkers, thirds: setting.showThirdMarkers)
        gridView.reset()
        store.snapOverlayActive = true

        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.cgID
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let scale = min(480 / display.visibleFrame.width, 360 / display.visibleFrame.height)
        let size = CGSize(width: display.visibleFrame.width * scale + 20, height: display.visibleFrame.height * scale + 20)
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        gridView.frame = panel.contentView?.bounds ?? .zero
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gridView)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        installMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let outside = MainActor.assumeIsolated { self.map { event.window !== $0.panel } ?? false }
            if outside { Task { @MainActor in self?.cancel() } }
            return event
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    private func liveFrame(for selection: GridSelection) -> CGRect? {
        guard let display else { return nil }
        let inset = max(0, store.state.preferences.snapGap) / 2
        return geometry.frame(for: selection, in: display.visibleFrame).insetBy(dx: inset, dy: inset)
    }

    private func apply(_ selection: GridSelection?) {
        guard let target, selection != lastApplied else { return }
        lastApplied = selection
        if let selection, let frame = liveFrame(for: selection) {
            WindowAccess.place(target, at: frame, within: display?.visibleFrame)
        } else if let original {
            WindowAccess.place(target, at: original)
        }
    }

    private func commit(_ selection: GridSelection?) {
        guard let selection, let target, let original, let display else { cancel(); return }
        apply(selection)
        let after = WindowAccess.frame(of: target) ?? liveFrame(for: selection) ?? original
        history.append(SnapRecord(window: target, before: original, after: after))
        if history.count > 20 { history.removeFirst() }
        store.snapCommitted(window: target, rect: geometry.unitRect(for: selection), display: display)
        store.status = "Snapped to \(selection.columns.count)×\(selection.rows.count) cells on \(display.name)"
        hide()
    }

    private func cancel() {
        guard panel.isVisible else { return }
        apply(nil)
        hide()
    }

    private func hide() {
        removeMonitors()
        store.snapOverlayActive = false
        target = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.10; panel.animator().alphaValue = 0 }) {
            Task { @MainActor in
                if !self.store.snapOverlayActive { self.panel.orderOut(nil) }
            }
        }
    }

    // Toggles the most recent snap: the first press restores the original frame, the next re-applies it.
    func undoOrRedo() {
        while let last = history.last {
            guard WindowAccess.frame(of: last.window) != nil else { history.removeLast(); continue }
            WindowAccess.place(last.window, at: last.undone ? last.after : last.before)
            history[history.count - 1].undone.toggle()
            store.status = last.undone ? "Redid snap" : "Undid snap"
            store.log(store.status)
            return
        }
        store.status = "No snap to undo"
    }

    func captureFocusedWindowAfterMenu() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            store.captureFocusedWindow()
        }
    }

    func showAfterMenu() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            show()
        }
    }
}
