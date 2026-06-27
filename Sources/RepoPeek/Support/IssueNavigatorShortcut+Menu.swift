import AppKit
import RepoPeekCore

extension MenuKeyboardShortcut {
    var menuKeyEquivalent: String {
        self.key
    }

    var menuKeyEquivalentModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if self.modifiers.contains(.command) { flags.insert(.command) }
        if self.modifiers.contains(.shift) { flags.insert(.shift) }
        if self.modifiers.contains(.option) { flags.insert(.option) }
        if self.modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    init?(event: NSEvent) {
        let key = Self.normalizedKeyEquivalent(from: event)
        guard key.isEmpty == false else { return nil }

        let modifiers = MenuKeyboardShortcutModifier.modifiers(from: event.modifierFlags)
        guard modifiers.contains(.command)
            || modifiers.contains(.control)
            || modifiers.contains(.option)
        else { return nil }

        self.init(key: key, modifiers: modifiers)
    }

    private static func normalizedKeyEquivalent(from event: NSEvent) -> String {
        guard let characters = event.charactersIgnoringModifiers ?? event.characters,
              characters.isEmpty == false
        else { return "" }

        if characters == "\r" { return "\r" }
        if characters == "\t" { return "\t" }
        if characters == " " { return " " }
        if characters.unicodeScalars.count == 1 {
            return characters.lowercased()
        }
        return ""
    }
}

private extension MenuKeyboardShortcutModifier {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<MenuKeyboardShortcutModifier> {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<MenuKeyboardShortcutModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
