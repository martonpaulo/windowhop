import XCTest
@testable import WindowHopCore

final class ShortcutSpecTests: XCTestCase {
    func testHoldModifiers() {
        XCTAssertEqual(ShortcutSpec.commandTab.holdModifier, .maskCommand)
        XCTAssertEqual(ShortcutSpec.optionTab.holdModifier, .maskAlternate)
        XCTAssertEqual(ShortcutSpec.controlTab.holdModifier, .maskControl)
    }

    func testDisplayNames() {
        XCTAssertEqual(ShortcutSpec.commandTab.displayName, "⌘ Tab")
        XCTAssertEqual(ShortcutSpec.optionTab.displayName, "⌥ Tab")
        XCTAssertEqual(ShortcutSpec.controlTab.displayName, "⌃ Tab")
    }

    func testRawValuesAreStable() {
        // persisted in UserDefaults; renaming cases would silently reset user settings
        XCTAssertEqual(ShortcutSpec.commandTab.rawValue, "commandTab")
        XCTAssertEqual(ShortcutSpec.optionTab.rawValue, "optionTab")
        XCTAssertEqual(ShortcutSpec.controlTab.rawValue, "controlTab")
    }
}
