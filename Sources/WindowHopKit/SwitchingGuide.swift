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

    public init(switcherShortcut: ShortcutSpec,
                persistentShortcut: PersistentShortcut?,
                enabled: Bool) {
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
        return Phrase(
            display: "Hold \(modifier.display) and press \(tab.display) to cycle through windows "
                + "(add \(shift.display) to go back). Release \(modifier.display) to switch.",
            spoken: "Hold \(modifier.spoken) and press \(tab.spoken) to cycle through windows "
                + "(add \(shift.spoken) to go back). Release \(modifier.spoken) to switch.")
    }

    private static func persistentSession(_ shortcut: PersistentShortcut?) -> Phrase {
        guard let shortcut else {
            let text = "Open WindowHop has no shortcut. Record one in Shortcuts to keep the "
                + "switcher open without holding a key."
            return Phrase(display: text, spoken: text)
        }
        let tab = key(KeyCode.tab)
        let returnKey = key(KeyCode.returnKey)
        let space = key(KeyCode.space)
        let escape = key(KeyCode.escape)
        return Phrase(
            display: "Press \(shortcut.displayString) to open WindowHop without holding a key. "
                + "\(tab.display) or the arrow keys move, \(returnKey.display) or "
                + "\(space.display) switches, \(escape.display) cancels.",
            spoken: "Press \(shortcut.spokenString) to open WindowHop without holding a key. "
                + "\(tab.spoken) or the arrow keys move, \(returnKey.spoken) or "
                + "\(space.spoken) switches, \(escape.spoken) cancels.")
    }

    private static let closeWindow: Phrase = {
        let delete = key(KeyCode.delete)
        return Phrase(
            display: "In either session, \(delete.display) closes the selected window after you confirm.",
            spoken: "In either session, \(delete.spoken) closes the selected window after you confirm.")
    }()

    private static let disabled = Phrase(
        display: "WindowHop is off. \(nativeSwitcherChord.display) opens the native app switcher.",
        spoken: "WindowHop is off. \(nativeSwitcherChord.spoken) opens the native app switcher.")

    private static func key(_ keyCode: Int64) -> Phrase {
        Phrase(display: ShortcutFormatter.keySymbol(for: keyCode),
               spoken: ShortcutFormatter.spokenKeyName(for: keyCode))
    }

    private static func key(modifiers: CGEventFlags) -> Phrase {
        Phrase(display: ShortcutFormatter.modifierSymbols(modifiers),
               spoken: ShortcutFormatter.spokenModifiers(modifiers))
    }
}
