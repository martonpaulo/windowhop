import CoreGraphics
import Foundation

/// Translates a physical key into the character it types on a keyboard layout,
/// without modifiers. The Engine supplies the live layout (`KeyboardLayout`);
/// the Core never reads it, so tests use fixture layouts.
public protocol KeyLabelSource {
    /// The character the key produces, or nil when the layout cannot say.
    func character(forKeyCode keyCode: UInt16) -> String?
}

/// The fixed US ANSI names: the fallback when no layout is installed or
/// translation fails. Deterministic, so tests never depend on the machine.
public struct ANSIKeyLabels: KeyLabelSource {
    public init() {}

    public func character(forKeyCode keyCode: UInt16) -> String? {
        KeyCodeNames.printableName(for: Int64(keyCode))
    }
}

/// The single source of truth for presenting keyboard shortcuts, following macOS
/// conventions: modifier glyphs in the canonical ⌃⌥⇧⌘ order, standard key glyphs
/// (⇥ ↩ ⎋ ⌫ ⌦, arrows), and Apple's textual "Space". Settings, the recorder,
/// help text, accessibility labels, and menus must all format through here —
/// never hardcode a second representation of the same key.
///
/// A shortcut is bound to a physical key code; only its label follows the
/// keyboard layout. Printable keys are named by `keyLabels` (on German QWERTZ
/// the key US calls Z shows as Y); special keys (Tab, Return, Space, Escape,
/// Delete, arrows, Home/End/Page keys, F1–F12) keep their canonical glyphs and
/// spoken names on every layout.
public enum ShortcutFormatter {
    /// Where printable key names come from. Main-thread state: the app installs
    /// the live layout at launch; until then, and in tests, the ANSI table.
    public static var keyLabels: KeyLabelSource = ANSIKeyLabels()

    public static func modifierSymbols(_ modifiers: CGEventFlags) -> String {
        var symbols = ""
        if modifiers.contains(.maskControl) { symbols += "⌃" }
        if modifiers.contains(.maskAlternate) { symbols += "⌥" }
        if modifiers.contains(.maskShift) { symbols += "⇧" }
        if modifiers.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    public static func keySymbol(for keyCode: Int64) -> String {
        printableCharacter(for: keyCode).map(displayForm) ?? KeyCodeNames.name(for: keyCode)
    }

    /// The character a printable key types on the current layout, as the
    /// layout reports it (not uppercased), or nil when the key is special, out
    /// of range, or the layout gives no single visible character. Shortcut
    /// conflict rules compare this with menu key equivalents.
    public static func printableCharacter(
        for keyCode: Int64, using labels: KeyLabelSource = ShortcutFormatter.keyLabels
    ) -> String? {
        guard !KeyCodeNames.isSpecial(keyCode),
              let code = UInt16(exactly: keyCode),
              let character = labels.character(forKeyCode: code),
              isSingleVisibleCharacter(character)
        else { return nil }
        return character
    }

    /// Exactly one grapheme cluster (which may span several scalars or UTF-16
    /// units), neither whitespace nor a control character.
    private static func isSingleVisibleCharacter(_ string: String) -> Bool {
        guard string.count == 1, let character = string.first else { return false }
        return !character.isWhitespace
            && !character.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// Uppercased the way menus show shortcut letters, unless uppercasing would
    /// turn one character into several (German ß stays ß rather than SS).
    private static func displayForm(_ character: String) -> String {
        let upper = character.uppercased()
        return upper.count == 1 ? upper : character
    }

    public static func chord(modifiers: CGEventFlags, keyCode: Int64) -> String {
        modifierSymbols(modifiers) + keySymbol(for: keyCode)
    }

    /// Spoken form for accessibility labels ("Command Tab", not "⌘⇥").
    public static func spokenChord(modifiers: CGEventFlags, keyCode: Int64) -> String {
        let spokenModifiers = spokenModifiers(modifiers)
        let key = spokenKeyName(for: keyCode)
        return spokenModifiers.isEmpty ? key : spokenModifiers + " " + key
    }

    /// Spoken modifier names in the same canonical order as `modifierSymbols`.
    public static func spokenModifiers(_ modifiers: CGEventFlags) -> String {
        var parts = [String]()
        if modifiers.contains(.maskControl) { parts.append("Control") }
        if modifiers.contains(.maskAlternate) { parts.append("Option") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskCommand) { parts.append("Command") }
        return parts.joined(separator: " ")
    }

    /// Spoken name of a single key ("Escape", not "⎋"); a printable key is
    /// spoken as the character its current label shows.
    public static func spokenKeyName(for keyCode: Int64) -> String {
        spokenKeyNames[keyCode] ?? keySymbol(for: keyCode)
    }

    private static let spokenKeyNames: [Int64: String] = [
        KeyCode.tab: "Tab",
        KeyCode.returnKey: "Return",
        KeyCode.keypadEnter: "Enter",
        KeyCode.escape: "Escape",
        KeyCode.space: "Space",
        KeyCode.delete: "Delete",
        KeyCode.forwardDelete: "Forward Delete",
        KeyCode.leftArrow: "Left Arrow",
        KeyCode.rightArrow: "Right Arrow",
        KeyCode.downArrow: "Down Arrow",
        KeyCode.upArrow: "Up Arrow",
    ]
}
