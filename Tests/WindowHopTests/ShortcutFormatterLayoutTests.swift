import XCTest
@testable import WindowHopCore

/// Printable shortcut keys are labelled by the current keyboard layout; special
/// keys keep one canonical name; the stored binding stays the physical key
/// code. Every layout here is a fixture, so nothing depends on or changes the
/// machine's input sources.
final class ShortcutFormatterLayoutTests: XCTestCase {
    /// A layout reduced to the keys a test needs; every other key has no character.
    private struct FixtureLayout: KeyLabelSource {
        let characters: [UInt16: String]
        let onQuery: ((UInt16) -> Void)?

        init(_ characters: [UInt16: String], onQuery: ((UInt16) -> Void)? = nil) {
            self.characters = characters
            self.onQuery = onQuery
        }

        func character(forKeyCode keyCode: UInt16) -> String? {
            onQuery?(keyCode)
            return characters[keyCode]
        }
    }

    private static let us = FixtureLayout([0: "a", 6: "z", 12: "q", 16: "y", 33: "["])
    private static let german = FixtureLayout([0: "a", 6: "y", 16: "z", 27: "ß", 33: "ü"])
    private static let french = FixtureLayout([0: "q", 6: "w", 12: "a", 16: "y", 33: "^"])

    private static let specialKeys: [Int64] = [
        KeyCode.tab, KeyCode.space, KeyCode.returnKey, KeyCode.escape, KeyCode.delete,
        KeyCode.forwardDelete, KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow,
        KeyCode.downArrow, 96, /* F5 */
    ]

    override func tearDown() {
        ShortcutFormatter.keyLabels = ANSIKeyLabels()
        super.tearDown()
    }

    private func labels(_ keyCodes: [Int64], under layout: KeyLabelSource) -> [String] {
        ShortcutFormatter.keyLabels = layout
        return keyCodes.map(ShortcutFormatter.keySymbol(for:))
    }

    func testPrintableKeysFollowTheLayout() {
        XCTAssertEqual(labels([0, 6, 16], under: Self.us), ["A", "Z", "Y"])
        XCTAssertEqual(labels([6, 16], under: Self.german), ["Y", "Z"])
        XCTAssertEqual(labels([0, 12], under: Self.french), ["Q", "A"])
    }

    func testTheStoredBindingIsThePhysicalKey() {
        let shortcut = PersistentShortcut(keyCode: 6, modifiers: [.maskAlternate])
        ShortcutFormatter.keyLabels = Self.us
        XCTAssertEqual(shortcut.displayString, "⌥Z")

        ShortcutFormatter.keyLabels = Self.german

        XCTAssertEqual(shortcut.displayString, "⌥Y")
        XCTAssertEqual(shortcut.keyCode, 6, "a layout change never rewrites the binding")
        XCTAssertEqual(shortcut.encoded, "\(CGEventFlags.maskAlternate.rawValue):6")
        XCTAssertTrue(shortcut.matches(keyCode: 6, flags: [.maskAlternate]))
    }

    func testDeadKeyShowsItsOwnCharacter() {
        XCTAssertEqual(labels([33], under: Self.french), ["^"])
    }

    func testSpecialKeysKeepCanonicalNamesUnderEveryLayout() {
        var queried = [UInt16]()
        let recording = FixtureLayout([48: "x", 49: "y", 36: "z"]) { queried.append($0) }
        let canonical = Self.specialKeys.map(KeyCodeNames.name(for:))
        XCTAssertEqual(canonical, ["⇥", "Space", "↩", "⎋", "⌫", "⌦", "←", "→", "↑", "↓", "F5"])

        for layout: KeyLabelSource in [Self.us, Self.german, Self.french, recording] {
            XCTAssertEqual(labels(Self.specialKeys, under: layout), canonical)
            XCTAssertEqual(Self.specialKeys.map(ShortcutFormatter.spokenKeyName(for:)),
                           ["Tab", "Space", "Return", "Escape", "Delete", "Forward Delete",
                            "Left Arrow", "Right Arrow", "Up Arrow", "Down Arrow", "F5"])
        }
        XCTAssertEqual(queried, [], "special keys never reach the layout")
    }

    func testUntranslatableKeysFallBackToTheANSITable() {
        let empty = FixtureLayout([0: "", 1: "\u{10}", 2: " ", 3: "ab", 4: "\t"])
        XCTAssertEqual(labels([0, 1, 2, 3, 4, 5], under: empty), ["A", "S", "D", "F", "H", "G"],
                       "empty, control, whitespace, multi-character and missing results fall back")
    }

    func testOutOfRangeKeyCodesNeverReachTheLayout() {
        var queried = [UInt16]()
        let layout = FixtureLayout([:]) { queried.append($0) }

        XCTAssertEqual(labels([300, -1, 70_000], under: layout), ["Key 300", "Key -1", "Key 70000"])
        XCTAssertEqual(queried, [300], "only a key code that fits UInt16 is translated")
    }

    func testMultiScalarCharactersStayWhole() {
        let combining = "e\u{301}"        // one grapheme, two scalars
        let nonBMP = "\u{1D4B6}"          // one scalar, two UTF-16 units
        let layout = FixtureLayout([0: combining, 1: nonBMP])

        XCTAssertEqual(labels([0, 1], under: layout), [combining.uppercased(), nonBMP])
    }

    func testUppercasingNeverSplitsACharacter() {
        XCTAssertEqual(labels([27], under: Self.german), ["ß"], "not SS")
    }

    func testSpokenStringsFollowTheSamePrintableRule() {
        ShortcutFormatter.keyLabels = Self.german
        let shortcut = PersistentShortcut(keyCode: 6, modifiers: [.maskAlternate])

        XCTAssertEqual(shortcut.spokenString, "Option Y")
        XCTAssertEqual(ShortcutFormatter.spokenChord(modifiers: .maskCommand, keyCode: KeyCode.tab),
                       "Command Tab")
    }

    func testPrintableCharacterIsTheLayoutsOwnForm() {
        ShortcutFormatter.keyLabels = Self.french
        XCTAssertEqual(ShortcutFormatter.printableCharacter(for: 12), "a")
        XCTAssertNil(ShortcutFormatter.printableCharacter(for: KeyCode.space))
        XCTAssertNil(ShortcutFormatter.printableCharacter(for: 40), "no character, no guess")
    }

    func testDefaultSourceIsTheANSITable() {
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: 6), "Z")
        XCTAssertEqual(ShortcutFormatter.keySymbol(for: 12), "Q")
    }
}
