import CoreGraphics
import Foundation

/// How to switch windows with the shortcuts configured right now. Settings
/// shows the status line at the top of General, a one-line hint under each
/// shortcut, and the session keys as a table in Shortcuts. Every key label
/// comes from `ShortcutFormatter`, so a changed shortcut changes the copy with
/// it.
///
/// Intentionally non-configurable: it is explanatory copy derived from
/// existing preferences, with no state of its own.
public struct SwitchingGuide: Equatable, Sendable {
    /// One phrase, visible and spoken. The spoken form names keys in words
    /// ("Command", "Escape") because VoiceOver reads glyphs inconsistently.
    public struct Phrase: Equatable, Sendable {
        public let display: String
        public let spoken: String
    }

    /// One action a session understands, with the keys that perform it, each
    /// drawn as its own key cap.
    public struct KeyRow: Equatable, Sendable, Identifiable {
        public let action: String
        public let keys: [Phrase]

        public var id: String { action }

        /// The row for VoiceOver: the action, then its keys in words.
        public var spoken: String {
            let keyNames = keys.map(\.spoken).joined(separator: String(localized: " or "))
            return String(
                localized: "\(action): \(keyNames)",
                comment: "An action in the switcher, then the keys that perform it.")
        }
    }

    /// Whether WindowHop is switching windows, and with which chord.
    public let status: Phrase
    /// Under the switcher shortcut: how the held session works.
    public let heldHint: Phrase
    /// Under Open WindowHop: how the persistent session works, or that it has
    /// no shortcut yet.
    public let persistentHint: Phrase
    /// The keys that work in either session, one row per action. They describe
    /// the configured shortcuts whether or not WindowHop is enabled.
    public let sessionKeys: [KeyRow]

    public init(
        switcherShortcut: ShortcutSpec,
        persistentShortcut: PersistentShortcut?,
        enabled: Bool
    ) {
        status =
            enabled
            ? Self.enabledStatus(switcherShortcut)
            : Self.disabledStatus
        heldHint = Self.heldHint(switcherShortcut)
        persistentHint = Self.persistentHint(persistentShortcut)
        sessionKeys = Self.sessionKeyRows()
    }

    /// The native app switcher's chord, which WindowHop hands back when it is
    /// off or not running.
    public static let nativeSwitcherChord = Phrase(
        display: ShortcutFormatter.chord(modifiers: .maskCommand, keyCode: KeyCode.tab),
        spoken: ShortcutFormatter.spokenChord(modifiers: .maskCommand, keyCode: KeyCode.tab))

    // MARK: - Phrases

    private static func enabledStatus(_ spec: ShortcutSpec) -> Phrase {
        let chord = Phrase(
            display: ShortcutFormatter.chord(modifiers: spec.holdModifier, keyCode: KeyCode.tab),
            spoken: ShortcutFormatter.spokenChord(modifiers: spec.holdModifier, keyCode: KeyCode.tab))
        func sentence(_ chord: String) -> String {
            String(
                localized: "On. \(chord) switches windows.",
                comment: "The placeholder is the switcher shortcut, such as ⌘⇥.")
        }
        return Phrase(display: sentence(chord.display), spoken: sentence(chord.spoken))
    }

    private static let disabledStatus: Phrase = {
        func sentence(_ chord: String) -> String {
            String(
                localized: "Off. \(chord) opens the native app switcher.",
                comment: "The placeholder is the native app switcher shortcut, ⌘⇥.")
        }
        return Phrase(
            display: sentence(nativeSwitcherChord.display),
            spoken: sentence(nativeSwitcherChord.spoken))
    }()

    private static func heldHint(_ spec: ShortcutSpec) -> Phrase {
        let modifier = key(modifiers: spec.holdModifier)
        let tab = key(KeyCode.tab)
        func sentence(_ modifier: String, _ tab: String) -> String {
            String(
                localized: "Hold \(modifier) and press \(tab). Release \(modifier) to switch.",
                comment: "Placeholders are key names or symbols: the held modifier, Tab.")
        }
        return Phrase(
            display: sentence(modifier.display, tab.display),
            spoken: sentence(modifier.spoken, tab.spoken))
    }

    private static func persistentHint(_ shortcut: PersistentShortcut?) -> Phrase {
        guard shortcut != nil else {
            let text = String(localized: "No shortcut. Record one to open the switcher without holding a key.")
            return Phrase(display: text, spoken: text)
        }
        let returnKey = key(KeyCode.returnKey)
        let space = key(KeyCode.space)
        func sentence(_ returnKey: String, _ space: String) -> String {
            String(
                localized: "Stays open without holding a key. \(returnKey) or \(space) switches.",
                comment: "Placeholders are key names or symbols: Return, Space.")
        }
        return Phrase(
            display: sentence(returnKey.display, space.display),
            spoken: sentence(returnKey.spoken, space.spoken))
    }

    /// Mirrors the session keys `EventTap.sessionEvent` maps. Space is left out:
    /// it switches only in the persistent session, and its hint says so. Built
    /// on every call, because ⌘, is labelled by the current keyboard layout.
    private static func sessionKeyRows() -> [KeyRow] {
        [
            KeyRow(
                action: String(localized: "Next window"),
                keys: [key(KeyCode.tab), key(KeyCode.rightArrow)]),
            KeyRow(
                action: String(localized: "Previous window"),
                keys: [chord(.maskShift, KeyCode.tab), key(KeyCode.leftArrow)]),
            KeyRow(
                action: String(localized: "Switch to the selected window"),
                keys: [key(KeyCode.returnKey)]),
            KeyRow(
                action: String(localized: "Close the selected window…"),
                keys: [key(KeyCode.delete)]),
            KeyRow(
                action: String(localized: "Open Settings"),
                keys: [chord(.maskCommand, KeyCode.comma)]),
            KeyRow(
                action: String(localized: "Cancel"),
                keys: [key(KeyCode.escape)]),
        ]
    }

    private static func key(_ keyCode: Int64) -> Phrase {
        Phrase(
            display: ShortcutFormatter.keySymbol(for: keyCode),
            spoken: ShortcutFormatter.spokenKeyName(for: keyCode))
    }

    private static func chord(_ modifiers: CGEventFlags, _ keyCode: Int64) -> Phrase {
        Phrase(
            display: ShortcutFormatter.chord(modifiers: modifiers, keyCode: keyCode),
            spoken: ShortcutFormatter.spokenChord(modifiers: modifiers, keyCode: keyCode))
    }

    private static func key(modifiers: CGEventFlags) -> Phrase {
        Phrase(
            display: ShortcutFormatter.modifierSymbols(modifiers),
            spoken: ShortcutFormatter.spokenModifiers(modifiers))
    }
}
