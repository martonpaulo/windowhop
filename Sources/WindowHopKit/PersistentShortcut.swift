import CoreGraphics
import Foundation

/// The configurable "Open WindowHop" shortcut: any modifier+key chord that opens a
/// persistent switcher session (no held modifier required).
///
/// Identity is physical: `keyCode` is the virtual key code that is stored and
/// that `EventTap` matches. A keyboard-layout change never rewrites it; only the
/// label `ShortcutFormatter` shows for the key follows the current layout.
public struct PersistentShortcut: Equatable, Sendable {
    /// Only these modifiers participate in matching and display.
    public static let relevantModifiers: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    public let keyCode: Int64
    public let modifiersRaw: UInt64

    public static let optionTab = PersistentShortcut(
        keyCode: KeyCode.tab, modifiers: [.maskAlternate])

    public init(keyCode: Int64, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        modifiersRaw = modifiers.intersection(PersistentShortcut.relevantModifiers).rawValue
    }

    public var modifiers: CGEventFlags { CGEventFlags(rawValue: modifiersRaw) }

    /// Exact chord match: the pressed key and precisely these modifiers.
    public func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode
            && flags.intersection(PersistentShortcut.relevantModifiers) == modifiers
    }

    // MARK: - Validation

    public enum ValidationError: Equatable, Sendable {
        case needsModifier
        case conflictsWithSwitcherShortcut
        /// A chord macOS keeps for itself, such as Force Quit (⌘⌥⎋).
        case reservedByMacOS(chord: String)
        /// A standard app command such as Quit (⌘Q): taking it globally would
        /// disable that command in every app while WindowHop runs.
        case standardApplicationCommand(chord: String, command: String)

        /// The modifiers that make a chord valid on their own (Shift alone does not),
        /// listed in the order the explanation names them.
        static let qualifyingModifiers: [CGEventFlags] =
            [.maskCommand, .maskAlternate, .maskControl]

        public var explanation: String {
            switch self {
            case .needsModifier:
                let glyphs = ValidationError.qualifyingModifiers
                    .map(ShortcutFormatter.modifierSymbols)
                    .joined(separator: ", ")
                return String(
                    localized: "Add at least one modifier key (\(glyphs)) so normal typing can't open WindowHop.")
            case .conflictsWithSwitcherShortcut:
                return String(localized: "This is already the switcher shortcut. Choose a different combination.")
            case .reservedByMacOS(let chord):
                return String(localized: "\(chord) is reserved by macOS. Choose a different combination.")
            case .standardApplicationCommand(let chord, let command):
                return String(
                    localized: """
                        \(chord) is the \(command) command in apps. \
                        Choose a combination that isn't a standard app command.
                        """,
                    comment:
                        "The first placeholder is a shortcut such as ⌘Q; the second is a command name such as Quit.")
            }
        }
    }

    /// nil means the shortcut is valid alongside the given switcher shortcut.
    public func validate(against switcherShortcut: ShortcutSpec) -> ValidationError? {
        let nonShiftModifiers = modifiers.subtracting(.maskShift)
        if nonShiftModifiers.isEmpty {
            return .needsModifier
        }
        if keyCode == KeyCode.tab,
            nonShiftModifiers == switcherShortcut.holdModifier
        {
            return .conflictsWithSwitcherShortcut
        }
        return nil
    }

    // MARK: - Persistence (UserDefaults string)

    public var encoded: String { "\(modifiersRaw):\(keyCode)" }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2, let modifiers = UInt64(parts[0]), let key = Int64(parts[1]) else {
            return nil
        }
        self.init(keyCode: key, modifiers: CGEventFlags(rawValue: modifiers))
    }

    // MARK: - Display

    public var displayString: String {
        ShortcutFormatter.chord(modifiers: modifiers, keyCode: keyCode)
    }

    public var spokenString: String {
        ShortcutFormatter.spokenChord(modifiers: modifiers, keyCode: keyCode)
    }
}

/// Fallback names for virtual key codes, owned by `ShortcutFormatter`. Printable
/// keys use the US ANSI characters, the fallback when the current layout cannot
/// name a key; special keys have one canonical glyph on every layout.
public enum KeyCodeNames {
    private static let printableNames: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
    ]

    private static let specialNames: [Int64: String] = [
        36: "↩", 48: "⇥", 49: String(localized: "Space"), 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    public static func name(for keyCode: Int64) -> String {
        // String(keyCode): an integer interpolated into String(localized:) is formatted
        // for the user's locale ("Key 70 000"); a key code is an identifier, not a quantity
        specialNames[keyCode] ?? printableNames[keyCode]
            ?? String(localized: "Key \(String(keyCode))", comment: "The placeholder is a virtual key code.")
    }

    /// The US ANSI character of a printable key; nil for any other key.
    public static func printableName(for keyCode: Int64) -> String? {
        printableNames[keyCode]
    }

    /// Keys whose name never follows the keyboard layout.
    public static func isSpecial(_ keyCode: Int64) -> Bool {
        specialNames[keyCode] != nil || keyCode == KeyCode.keypadEnter
    }
}
