import CoreGraphics
import Foundation
import Testing

@testable import WindowHopKit

@MainActor  // reads ShortcutFormatter.keyLabels (see ShortcutFormatterLayoutTests)
struct PersistentShortcutTests {
    @Test func exactModifierMatching() {
        let shortcut = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate])
        #expect(shortcut.matches(keyCode: KeyCode.space, flags: [.maskAlternate]))
        // extra relevant modifiers must not match
        #expect(!shortcut.matches(keyCode: KeyCode.space, flags: [.maskAlternate, .maskShift]))
        #expect(!shortcut.matches(keyCode: KeyCode.space, flags: [.maskCommand]))
        #expect(!shortcut.matches(keyCode: KeyCode.tab, flags: [.maskAlternate]))
        // irrelevant flags (caps lock, fn, key-pad bits) are ignored
        var flags: CGEventFlags = [.maskAlternate]
        flags.insert(.maskAlphaShift)
        flags.insert(.maskNonCoalesced)
        #expect(shortcut.matches(keyCode: KeyCode.space, flags: flags))
    }

    @Test func modifierOnlyOrBareKeyIsRejected() {
        #expect(
            PersistentShortcut(keyCode: 0, modifiers: []).validate(against: .commandTab) == .needsModifier)
        // Shift alone is not enough: shift+letter is normal typing
        #expect(
            PersistentShortcut(keyCode: 0, modifiers: [.maskShift]).validate(against: .commandTab) == .needsModifier)
    }

    /// The glyphs in the message come from ShortcutFormatter, never a second
    /// hardcoded representation (issue #114).
    @Test func needsModifierExplanationUsesFormatterGlyphs() {
        let glyphs = [CGEventFlags.maskCommand, .maskAlternate, .maskControl]
            .map(ShortcutFormatter.modifierSymbols)
            .joined(separator: ", ")
        #expect(
            PersistentShortcut.ValidationError.needsModifier.explanation
                == "Add at least one modifier key (\(glyphs)) so normal typing can't open WindowHop.")
        // every modifier the message names is, on its own, enough to pass validation
        for modifier in PersistentShortcut.ValidationError.qualifyingModifiers {
            #expect(
                PersistentShortcut(keyCode: KeyCode.space, modifiers: modifier)
                    .validate(against: .commandTab) == nil)
        }
    }

    @Test func conflictWithSwitcherShortcutIsRejected() {
        let cmdTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskCommand])
        #expect(cmdTab.validate(against: .commandTab) == .conflictsWithSwitcherShortcut)
        let cmdShiftTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskCommand, .maskShift])
        #expect(cmdShiftTab.validate(against: .commandTab) == .conflictsWithSwitcherShortcut)
        // fine when the switcher uses a different hold modifier
        #expect(cmdTab.validate(against: .optionTab) == nil)
        let optionTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskAlternate])
        #expect(optionTab.validate(against: .optionTab) == .conflictsWithSwitcherShortcut)
    }

    @Test func validShortcuts() {
        #expect(
            PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate]).validate(against: .commandTab)
                == nil)
        // key code 40 is K
        #expect(
            PersistentShortcut(keyCode: 40, modifiers: [.maskCommand, .maskShift]).validate(
                against: .commandTab) == nil)
    }

    @Test func encodingRoundTrip() {
        let original = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskControl, .maskAlternate])
        let decoded = PersistentShortcut(encoded: original.encoded)
        #expect(decoded == original)
        #expect(PersistentShortcut(encoded: "") == nil)
        #expect(PersistentShortcut(encoded: "garbage") == nil)
        #expect(PersistentShortcut(encoded: "1:2:3") == nil)
    }

    @Test func displayString() {
        #expect(PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate]).displayString == "⌥Space")
        #expect(
            PersistentShortcut(keyCode: 40, modifiers: [.maskControl, .maskShift, .maskCommand]).displayString == "⌃⇧⌘K"
        )
    }

    @Test func preferencesDefaultIsOptionTabAndCanBeCleared() throws {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.persistentShortcut == .optionTab)
        let shortcut = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate])
        preferences.persistentShortcut = shortcut
        #expect(preferences.persistentShortcut == shortcut)
        preferences.persistentShortcut = nil
        #expect(preferences.persistentShortcut == nil)
        #expect(Preferences(defaults: defaults).persistentShortcut == nil)
    }
}
