// Portions adapted from GridSnap (https://github.com/konieczkow/gridsnap),
// Copyright (c) 2026 Maciej Gajewski, MIT License. See THIRD_PARTY_NOTICES.md.

import AppKit
import Carbon

struct HotKey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let defaultSnap = HotKey(keyCode: 5, modifiers: UInt32(controlKey | optionKey), label: "⌃⌥G")
    static let defaultUndo = HotKey(keyCode: 6, modifiers: UInt32(controlKey | optionKey), label: "⌃⌥Z")

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }

    // Returns nil for Escape or a key without a modifier, which keeps the old shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.keyCode != 53, !flags.isEmpty else { return nil }
        var mods: UInt32 = 0
        var label = ""
        for (flag, mod, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
                                    (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] where flags.contains(flag) {
            mods |= UInt32(mod)
            label += symbol
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods,
                  label: label + (event.charactersIgnoringModifiers?.uppercased() ?? "?"))
    }
}

@MainActor final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var onPress: ((UInt32) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handlerStatus: OSStatus?

    private func installHandler() -> OSStatus {
        if let handlerStatus { return handlerStatus }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let value = id.id
            Task { @MainActor in HotkeyCenter.shared.onPress?(value) }
            return noErr
        }, 1, &spec, nil, nil)
        handlerStatus = status
        return status
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
    }

    // Returns noErr on success, otherwise the Carbon error (eventHotKeyExistsErr when another app owns the shortcut).
    func register(_ key: HotKey, id: UInt32) -> OSStatus {
        let installed = installHandler()
        guard installed == noErr else { return installed }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key.keyCode, key.modifiers,
                                         EventHotKeyID(signature: 0x534C_534E, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
        return status
    }
}
