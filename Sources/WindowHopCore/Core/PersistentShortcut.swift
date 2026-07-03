import CoreGraphics
import Foundation

/// The optional "Open WindowHop" shortcut: any modifier+key chord that opens a
/// persistent switcher session (no held modifier required). Unassigned by default.
public struct PersistentShortcut: Equatable {
    /// Only these modifiers participate in matching and display.
    public static let relevantModifiers: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    public let keyCode: Int64
    public let modifiersRaw: UInt64

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

    public enum ValidationError: Equatable {
        case needsModifier
        case conflictsWithSwitcherShortcut

        public var explanation: String {
            switch self {
            case .needsModifier:
                return "Add at least one modifier key (⌘, ⌥, ⌃) so normal typing can't open WindowHop."
            case .conflictsWithSwitcherShortcut:
                return "This is already the switcher shortcut. Choose a different combination."
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
           nonShiftModifiers == switcherShortcut.holdModifier {
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
        var symbols = ""
        if modifiers.contains(.maskControl) { symbols += "⌃" }
        if modifiers.contains(.maskAlternate) { symbols += "⌥" }
        if modifiers.contains(.maskShift) { symbols += "⇧" }
        if modifiers.contains(.maskCommand) { symbols += "⌘" }
        return symbols + KeyCodeNames.name(for: keyCode)
    }
}

/// Human-readable names for common virtual key codes (US ANSI layout for letters,
/// which is how macOS conventionally displays shortcuts).
public enum KeyCodeNames {
    private static let names: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    public static func name(for keyCode: Int64) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
