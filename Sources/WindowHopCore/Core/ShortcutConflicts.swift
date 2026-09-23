import CoreGraphics
import Foundation

/// The one owner of which recorded Open WindowHop chords collide with macOS or
/// with standard app commands. The event tap consumes the chord in every app,
/// so a collision would silently disable the other command everywhere while
/// WindowHop runs.
///
/// Applied only when a chord is captured in Settings. A stored chord is never
/// re-assessed on load: existing choices are preserved (`validate(against:)`
/// stays the only load-time rule).
public enum ShortcutConflicts {
    /// A standard menu command, matched by character because menu key
    /// equivalents are characters, not physical keys.
    public struct StandardCommand: Equatable, Sendable {
        public let name: String
        public let character: String
        public let modifiers: CGEventFlags

        public init(_ name: String, _ character: String, _ modifiers: CGEventFlags = .maskCommand) {
            self.name = name
            self.character = character
            self.modifiers = modifiers
        }
    }

    /// The macOS standard app commands (Apple HIG, "Keyboard shortcuts":
    /// https://developer.apple.com/design/human-interface-guidelines/keyboard).
    public static let standardCommands: [StandardCommand] = [
        StandardCommand("Quit", "q"),
        StandardCommand("Hide", "h"),
        StandardCommand("Settings", ","),
        StandardCommand("Close", "w"),
        StandardCommand("Minimize", "m"),
        StandardCommand("New", "n"),
        StandardCommand("Open", "o"),
        StandardCommand("Save", "s"),
        StandardCommand("Print", "p"),
        StandardCommand("Find", "f"),
        StandardCommand("Undo", "z"),
        StandardCommand("Redo", "z", [.maskShift, .maskCommand]),
        StandardCommand("Cut", "x"),
        StandardCommand("Copy", "c"),
        StandardCommand("Paste", "v"),
        StandardCommand("Select All", "a"),
    ]

    /// Chords macOS hard-sets and users cannot turn off: Force Quit Applications
    /// (⌘⌥⎋), force quit the active app (⌘⌥⇧⎋) and ⌘⌥⌃⇧⎋. From AltTab's
    /// `MacOsShortcuts` (317a485b:src/ui/generic-components/CustomRecorderControlTestable.swift).
    public static let reservedByMacOS: [PersistentShortcut] = [
        PersistentShortcut(keyCode: KeyCode.escape, modifiers: [.maskCommand, .maskAlternate]),
        PersistentShortcut(keyCode: KeyCode.escape,
                           modifiers: [.maskCommand, .maskAlternate, .maskShift]),
        PersistentShortcut(keyCode: KeyCode.escape,
                           modifiers: [.maskCommand, .maskAlternate, .maskShift, .maskControl]),
    ]

    /// The standard command a chord would take over, if any. The key is named
    /// by the given layout, with the US ANSI table as the fallback, so on
    /// French AZERTY ⌘ + key code 12 is Select All, not Quit.
    public static func standardCommand(
        for shortcut: PersistentShortcut, labels: KeyLabelSource = ShortcutFormatter.keyLabels
    ) -> StandardCommand? {
        guard let character = ShortcutFormatter.printableCharacter(for: shortcut.keyCode, using: labels)
                ?? KeyCodeNames.printableName(for: shortcut.keyCode)
        else { return nil }
        let lowered = character.lowercased()
        return standardCommands.first {
            $0.character == lowered && $0.modifiers == shortcut.modifiers
        }
    }
}

extension PersistentShortcut {
    /// What Settings does with a freshly recorded chord.
    public enum CaptureAssessment: Equatable, Sendable {
        case accept
        case reject(ValidationError)
        /// An enabled macOS keyboard shortcut: usable, but only after the user
        /// confirms that WindowHop will take it over.
        case confirmSystemShortcut
    }

    /// Assesses a chord captured by the recorder, in order: the load-time rules
    /// (`validate(against:)`), then re-recording the current chord (always
    /// accepted, so an existing choice is never blocked), chords macOS reserves,
    /// standard app commands, and finally the enabled macOS shortcuts.
    ///
    /// - Parameters:
    ///   - current: the chord stored now, if any.
    ///   - systemShortcuts: the enabled macOS keyboard shortcuts.
    ///   - labels: the keyboard layout used to name printable keys.
    public func assessCapture(
        against switcherShortcut: ShortcutSpec,
        current: PersistentShortcut?,
        systemShortcuts: [PersistentShortcut],
        labels: KeyLabelSource = ShortcutFormatter.keyLabels
    ) -> CaptureAssessment {
        if let error = validate(against: switcherShortcut) {
            return .reject(error)
        }
        if self == current {
            return .accept
        }
        if ShortcutConflicts.reservedByMacOS.contains(self) {
            return .reject(.reservedByMacOS(chord: displayString))
        }
        if let command = ShortcutConflicts.standardCommand(for: self, labels: labels) {
            return .reject(.standardApplicationCommand(chord: displayString, command: command.name))
        }
        if systemShortcuts.contains(self) {
            return .confirmSystemShortcut
        }
        return .accept
    }

    /// Copy for the confirmation shown before taking over a macOS shortcut.
    public var systemShortcutConfirmation: (title: String, message: String) {
        ("\(displayString) is also a macOS shortcut",
         "While WindowHop is running, it takes over \(displayString) and macOS won't respond to it. "
            + "You can change the macOS shortcut in System Settings → Keyboard → Keyboard Shortcuts.")
    }
}
