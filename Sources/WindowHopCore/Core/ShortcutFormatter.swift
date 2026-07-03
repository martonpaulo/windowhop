import CoreGraphics
import Foundation

/// The single source of truth for presenting keyboard shortcuts, following macOS
/// conventions: modifier glyphs in the canonical ⌃⌥⇧⌘ order, standard key glyphs
/// (⇥ ↩ ⎋ ⌫ ⌦, arrows), and Apple's textual "Space". Settings, the recorder,
/// help text, accessibility labels, and menus must all format through here —
/// never hardcode a second representation of the same key.
public enum ShortcutFormatter {
    public static func modifierSymbols(_ modifiers: CGEventFlags) -> String {
        var symbols = ""
        if modifiers.contains(.maskControl) { symbols += "⌃" }
        if modifiers.contains(.maskAlternate) { symbols += "⌥" }
        if modifiers.contains(.maskShift) { symbols += "⇧" }
        if modifiers.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    public static func keySymbol(for keyCode: Int64) -> String {
        KeyCodeNames.name(for: keyCode)
    }

    public static func chord(modifiers: CGEventFlags, keyCode: Int64) -> String {
        modifierSymbols(modifiers) + keySymbol(for: keyCode)
    }

    /// Spoken form for accessibility labels ("Command Tab", not "⌘⇥").
    public static func spokenChord(modifiers: CGEventFlags, keyCode: Int64) -> String {
        var parts = [String]()
        if modifiers.contains(.maskControl) { parts.append("Control") }
        if modifiers.contains(.maskAlternate) { parts.append("Option") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskCommand) { parts.append("Command") }
        parts.append(spokenKeyNames[keyCode] ?? KeyCodeNames.name(for: keyCode))
        return parts.joined(separator: " ")
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
