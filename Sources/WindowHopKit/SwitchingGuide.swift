import CoreGraphics
import Foundation

/// How to switch windows with the shortcuts configured right now. Settings
/// shows it at the top of General, so a new user sees the first action as soon
/// as the permission is granted, and the Shortcuts pane explains the same keys
/// from the same sentences. Every key label comes from `ShortcutFormatter`, so
/// a changed shortcut changes the copy with it.
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

    /// The first switching actions: the held and the persistent session, or a
    /// single sentence saying that the native switcher is in charge.
    public let firstSteps: [Phrase]
    /// Every key the switcher understands, for the Shortcuts pane. It describes
    /// the configured shortcuts whether or not WindowHop is enabled.
    public let keyReference: [Phrase]

    public init(
        switcherShortcut: ShortcutSpec,
        persistentShortcut: PersistentShortcut?,
        enabled: Bool
    ) {
        let held = Self.heldSession(switcherShortcut)
        let persistent = Self.persistentSession(persistentShortcut)
        firstSteps = enabled ? [held, persistent] : [Self.disabled]
        keyReference = [held, persistent, Self.closeWindow]
    }

    /// The native app switcher's chord, which WindowHop hands back when it is
    /// off or not running.
    public static let nativeSwitcherChord = Phrase(
        display: ShortcutFormatter.chord(modifiers: .maskCommand, keyCode: KeyCode.tab),
        spoken: ShortcutFormatter.spokenChord(modifiers: .maskCommand, keyCode: KeyCode.tab))

    // MARK: - Phrases

    private static func heldSession(_ spec: ShortcutSpec) -> Phrase {
        let modifier = key(modifiers: spec.holdModifier)
        let tab = key(KeyCode.tab)
        let shift = key(modifiers: .maskShift)
        func sentence(_ modifier: String, _ tab: String, _ shift: String) -> String {
            String(
                localized: """
                    Hold \(modifier) and press \(tab) to cycle through windows \
                    (add \(shift) to go back). Release \(modifier) to switch.
                    """, comment: "Placeholders are key names or symbols: the held modifier, Tab, Shift.")
        }
        return Phrase(
            display: sentence(modifier.display, tab.display, shift.display),
            spoken: sentence(modifier.spoken, tab.spoken, shift.spoken))
    }

    private static func persistentSession(_ shortcut: PersistentShortcut?) -> Phrase {
        guard let shortcut else {
            let text = String(
                localized: """
                    Open WindowHop has no shortcut. Record one in Shortcuts to keep the \
                    switcher open without holding a key.
                    """)
            return Phrase(display: text, spoken: text)
        }
        let tab = key(KeyCode.tab)
        let returnKey = key(KeyCode.returnKey)
        let space = key(KeyCode.space)
        let escape = key(KeyCode.escape)
        func sentence(
            _ chord: String, _ tab: String, _ returnKey: String, _ space: String,
            _ escape: String
        ) -> String {
            String(
                localized: """
                    Press \(chord) to open WindowHop without holding a key. \
                    \(tab) or the arrow keys move, \(returnKey) or \(space) switches, \(escape) cancels.
                    """,
                comment:
                    "Placeholders are key names or symbols: the Open WindowHop shortcut, Tab, Return, Space, Escape.")
        }
        return Phrase(
            display: sentence(
                shortcut.displayString, tab.display, returnKey.display, space.display,
                escape.display),
            spoken: sentence(
                shortcut.spokenString, tab.spoken, returnKey.spoken, space.spoken,
                escape.spoken))
    }

    private static let closeWindow: Phrase = {
        let delete = key(KeyCode.delete)
        func sentence(_ delete: String) -> String {
            String(
                localized: "In either session, \(delete) closes the selected window after you confirm.",
                comment: "The placeholder is the Delete key's name or symbol.")
        }
        return Phrase(display: sentence(delete.display), spoken: sentence(delete.spoken))
    }()

    private static let disabled: Phrase = {
        func sentence(_ chord: String) -> String {
            String(
                localized: "WindowHop is off. \(chord) opens the native app switcher.",
                comment: "The placeholder is the native app switcher shortcut, ⌘Tab.")
        }
        return Phrase(
            display: sentence(nativeSwitcherChord.display),
            spoken: sentence(nativeSwitcherChord.spoken))
    }()

    private static func key(_ keyCode: Int64) -> Phrase {
        Phrase(
            display: ShortcutFormatter.keySymbol(for: keyCode),
            spoken: ShortcutFormatter.spokenKeyName(for: keyCode))
    }

    private static func key(modifiers: CGEventFlags) -> Phrase {
        Phrase(
            display: ShortcutFormatter.modifierSymbols(modifiers),
            spoken: ShortcutFormatter.spokenModifiers(modifiers))
    }
}
