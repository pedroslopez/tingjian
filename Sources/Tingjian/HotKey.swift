import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus modifiers, with a display label.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value (command / option / control / shift only).
    var modifierFlags: UInt
    /// Key label captured when recorded ("T", "Space", "F5", …).
    var key: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: [.option, .command], key: "T")

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.relevant).rawValue
        self.key = key
    }

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    /// "⌃⌥⇧⌘T", in the standard macOS order.
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    // MARK: Recording

    enum RecordResult {
        case shortcut(Shortcut)
        case clear
        case cancel
        case needsModifier
    }

    /// Interprets a key press while recording. Esc cancels, ⌫ clears the hotkey.
    /// Function keys may be used alone; anything else needs ⌘, ⌥ or ⌃.
    static func record(_ event: NSEvent) -> RecordResult {
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(relevant)
        if keyCode == kVK_Escape, modifiers.isEmpty { return .cancel }
        if keyCode == kVK_Delete || keyCode == kVK_ForwardDelete, modifiers.isEmpty { return .clear }
        let isFunctionKey = functionKeys[keyCode] != nil
        guard isFunctionKey || !modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return .needsModifier
        }
        return .shortcut(Shortcut(keyCode: UInt32(keyCode), modifiers: modifiers, key: label(for: event)))
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static func label(for event: NSEvent) -> String {
        let keyCode = Int(event.keyCode)
        if let name = functionKeys[keyCode] ?? namedKeys[keyCode] { return name }
        // The unmodified character, so ⌥⇧1 shows "1" rather than "⁄".
        let base = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        return base.isEmpty ? "Key \(keyCode)" : base
    }
}

/// System-wide hotkey via Carbon `RegisterEventHotKey`. Needs no permissions.
/// The shortcut can be swapped at runtime.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Registers `shortcut`, replacing any previous one. Returns false if macOS refuses
    /// it (e.g. a reserved combination); then nothing is registered. Carbon does not
    /// detect clashes with other apps' hotkeys.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x544A_4E48), id: 1)  // 'TJNH'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
