import CoreGraphics
import Foundation
import Testing

@testable import WindowHopKit

/// The switching guide is the copy Settings shows about switching. It must follow the shortcuts actually configured, and every
/// key label in it must be the one `ShortcutFormatter` produces.
@MainActor  // reads ShortcutFormatter.keyLabels (see ShortcutFormatterLayoutTests)
struct SwitchingGuideTests {
    private static let keyK: Int64 = 40

    private func guide(
        _ spec: ShortcutSpec = .commandTab,
        persistent: PersistentShortcut? = .optionTab,
        enabled: Bool = true
    ) -> SwitchingGuide {
        SwitchingGuide(switcherShortcut: spec, persistentShortcut: persistent, enabled: enabled)
    }

    @Test func eachSwitcherShortcutNamesItsOwnHoldModifier() {
        for spec in ShortcutSpec.allCases {
            let held = guide(spec).heldHint
            let glyph = ShortcutFormatter.modifierSymbols(spec.holdModifier)
            let spoken = ShortcutFormatter.spokenModifiers(spec.holdModifier)
            #expect(held.display.hasPrefix("Hold \(glyph) and press "), "\(held.display)")
            #expect(held.display.hasSuffix("Release \(glyph) to switch."), "\(held.display)")
            #expect(held.spoken == "Hold \(spoken) and press Tab. Release \(spoken) to switch.")
        }
    }

    @Test func statusNamesTheConfiguredChordWhenOn() {
        for spec in ShortcutSpec.allCases {
            let status = guide(spec).status
            let chord = ShortcutFormatter.chord(modifiers: spec.holdModifier, keyCode: KeyCode.tab)
            #expect(status.display == "On. \(chord) switches windows.")
            #expect(!status.spoken.contains(chord))
        }
    }

    @Test func disabledWindowHopHandsSwitchingToTheNativeSwitcher() {
        // whatever WindowHop's own shortcut is, the native switcher is ⌘⇥
        let status = guide(.optionTab, enabled: false).status
        #expect(status.display == "Off. ⌘⇥ opens the native app switcher.")
        #expect(status.spoken == "Off. Command Tab opens the native app switcher.")
    }

    @Test func persistentHintExplainsTheExplicitConfirmation() {
        let hint = guide().persistentHint
        #expect(hint.display == "Stays open without holding a key. ↩ or Space switches.")
        #expect(hint.spoken == "Stays open without holding a key. Return or Space switches.")
    }

    @Test func unassignedPersistentShortcutAsksForOne() {
        let hint = guide(persistent: nil).persistentHint
        #expect(hint.display.hasPrefix("No shortcut. Record one"))
        #expect(hint.spoken == hint.display)
    }

    @Test func sessionKeysDescribeTheShortcutsEvenWhenDisabled() {
        let rows = guide(enabled: true).sessionKeys
        #expect(guide(enabled: false).sessionKeys == rows)
        #expect(
            rows.map(\.action) == [
                "Next window", "Previous window", "Switch to the selected window",
                "Close the selected window…", "Open Settings", "Cancel",
            ])
        #expect(rows[1].keys.map(\.display) == ["⇧⇥", "←"])
        #expect(rows[5].spoken == "Cancel: Escape")
        #expect(rows[0].spoken == "Next window: Tab or Right Arrow")
    }

    /// Every key glyph in the copy is one the formatter produces for a key the
    /// sentence is about, so a second representation of a key cannot creep in.
    @Test func everyGlyphComesFromTheFormatter() {
        let custom = PersistentShortcut(keyCode: Self.keyK, modifiers: [.maskControl, .maskAlternate])
        let formatterGlyphs = Set(
            ([.maskControl, .maskAlternate, .maskShift, .maskCommand] as [CGEventFlags])
                .map(ShortcutFormatter.modifierSymbols)
                + [
                    KeyCode.tab, KeyCode.returnKey, KeyCode.escape, KeyCode.delete, KeyCode.forwardDelete,
                    KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow,
                ]
                .map(ShortcutFormatter.keySymbol))
        func glyphs(in text: String) -> Set<String> {
            Set(text.map(String.init)).intersection(formatterGlyphs)
        }

        for spec in ShortcutSpec.allCases {
            for persistent in [PersistentShortcut.optionTab, custom, nil] {
                let current = guide(spec, persistent: persistent)
                let phrases =
                    [current.status, current.heldHint, current.persistentHint]
                    + current.sessionKeys.flatMap(\.keys)
                let expected =
                    [
                        ShortcutFormatter.modifierSymbols(spec.holdModifier),
                        ShortcutFormatter.modifierSymbols([.maskShift, .maskCommand]),
                    ]
                    + [
                        KeyCode.tab, KeyCode.rightArrow, KeyCode.leftArrow, KeyCode.delete,
                        KeyCode.escape,
                    ].map(ShortcutFormatter.keySymbol)
                    + (persistent == nil ? [] : [ShortcutFormatter.keySymbol(for: KeyCode.returnKey)])
                    + [ShortcutFormatter.keySymbol(for: KeyCode.returnKey)]
                let text = phrases.map(\.display).joined(separator: " ")
                #expect(glyphs(in: text) == glyphs(in: expected.joined()), "\(text)")
                // the spoken form names keys in words only
                #expect(glyphs(in: phrases.map(\.spoken).joined()).isEmpty)
                #expect(glyphs(in: current.sessionKeys.map(\.spoken).joined()).isEmpty)
            }
        }
    }
}
