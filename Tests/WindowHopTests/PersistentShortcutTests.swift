import XCTest
@testable import WindowHopCore

final class PersistentShortcutTests: XCTestCase {
    func testExactModifierMatching() {
        let shortcut = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate])
        XCTAssertTrue(shortcut.matches(keyCode: KeyCode.space, flags: [.maskAlternate]))
        // extra relevant modifiers must not match
        XCTAssertFalse(shortcut.matches(keyCode: KeyCode.space, flags: [.maskAlternate, .maskShift]))
        XCTAssertFalse(shortcut.matches(keyCode: KeyCode.space, flags: [.maskCommand]))
        XCTAssertFalse(shortcut.matches(keyCode: KeyCode.tab, flags: [.maskAlternate]))
        // irrelevant flags (caps lock, fn, key-pad bits) are ignored
        var flags: CGEventFlags = [.maskAlternate]
        flags.insert(.maskAlphaShift)
        flags.insert(.maskNonCoalesced)
        XCTAssertTrue(shortcut.matches(keyCode: KeyCode.space, flags: flags))
    }

    func testModifierOnlyOrBareKeyIsRejected() {
        XCTAssertEqual(PersistentShortcut(keyCode: 0, modifiers: []).validate(against: .commandTab),
                       .needsModifier)
        // Shift alone is not enough: shift+letter is normal typing
        XCTAssertEqual(PersistentShortcut(keyCode: 0, modifiers: [.maskShift]).validate(against: .commandTab),
                       .needsModifier)
    }

    func testConflictWithSwitcherShortcutIsRejected() {
        let cmdTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskCommand])
        XCTAssertEqual(cmdTab.validate(against: .commandTab), .conflictsWithSwitcherShortcut)
        let cmdShiftTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(cmdShiftTab.validate(against: .commandTab), .conflictsWithSwitcherShortcut)
        // fine when the switcher uses a different hold modifier
        XCTAssertNil(cmdTab.validate(against: .optionTab))
        let optionTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskAlternate])
        XCTAssertEqual(optionTab.validate(against: .optionTab), .conflictsWithSwitcherShortcut)
    }

    func testValidShortcuts() {
        XCTAssertNil(PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate]).validate(against: .commandTab))
        XCTAssertNil(PersistentShortcut(keyCode: 40 /* K */, modifiers: [.maskCommand, .maskShift]).validate(against: .commandTab))
    }

    func testEncodingRoundTrip() {
        let original = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskControl, .maskAlternate])
        let decoded = PersistentShortcut(encoded: original.encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(PersistentShortcut(encoded: ""))
        XCTAssertNil(PersistentShortcut(encoded: "garbage"))
        XCTAssertNil(PersistentShortcut(encoded: "1:2:3"))
    }

    func testDisplayString() {
        XCTAssertEqual(PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate]).displayString, "⌥Space")
        XCTAssertEqual(PersistentShortcut(keyCode: 40, modifiers: [.maskControl, .maskShift, .maskCommand]).displayString,
                       "⌃⇧⌘K")
    }

    func testPreferencesDefaultIsOptionTabAndCanBeCleared() {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.persistentShortcut, .optionTab)
        let shortcut = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate])
        preferences.persistentShortcut = shortcut
        XCTAssertEqual(preferences.persistentShortcut, shortcut)
        preferences.persistentShortcut = nil
        XCTAssertNil(preferences.persistentShortcut)
        XCTAssertNil(Preferences(defaults: defaults).persistentShortcut)
    }
}
