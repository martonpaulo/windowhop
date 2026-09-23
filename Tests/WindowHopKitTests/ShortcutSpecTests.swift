import XCTest
@testable import WindowHopCore

final class ShortcutSpecTests: XCTestCase {
    func testHoldModifiers() {
        XCTAssertEqual(ShortcutSpec.commandTab.holdModifier, .maskCommand)
        XCTAssertEqual(ShortcutSpec.optionTab.holdModifier, .maskAlternate)
        XCTAssertEqual(ShortcutSpec.controlTab.holdModifier, .maskControl)
    }

    func testDisplayNamesUseTheSharedFormatter() {
        XCTAssertEqual(ShortcutSpec.commandTab.displayName, "⌘⇥")
        XCTAssertEqual(ShortcutSpec.optionTab.displayName, "⌥⇥")
        XCTAssertEqual(ShortcutSpec.controlTab.displayName, "⌃⇥")
    }

    func testFormatterConsistency() {
        // ShortcutSpec and PersistentShortcut must render identical chords identically
        let persistent = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskCommand])
        XCTAssertEqual(persistent.displayString, ShortcutSpec.commandTab.displayName)
    }

    func testFormatterKeyGlyphs() {
        XCTAssertEqual(ShortcutFormatter.chord(modifiers: [.maskCommand, .maskShift], keyCode: KeyCode.tab), "⇧⌘⇥")
        XCTAssertEqual(ShortcutFormatter.chord(modifiers: [.maskAlternate], keyCode: KeyCode.space), "⌥Space")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.returnKey), "↩")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.escape), "⎋")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.delete), "⌫")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.forwardDelete), "⌦")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.leftArrow), "←")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.rightArrow), "→")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.upArrow), "↑")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: KeyCode.downArrow), "↓")
    }

    func testSpokenChordForAccessibility() {
        XCTAssertEqual(ShortcutFormatter.spokenChord(modifiers: [.maskCommand, .maskShift], keyCode: KeyCode.tab),
                       "Shift Command Tab")
        XCTAssertEqual(ShortcutFormatter.spokenChord(modifiers: [.maskAlternate], keyCode: KeyCode.space),
                       "Option Space")
    }

    func testRawValuesAreStable() {
        // persisted in UserDefaults; renaming cases would silently reset user settings
        XCTAssertEqual(ShortcutSpec.commandTab.rawValue, "commandTab")
        XCTAssertEqual(ShortcutSpec.optionTab.rawValue, "optionTab")
        XCTAssertEqual(ShortcutSpec.controlTab.rawValue, "controlTab")
    }
}
