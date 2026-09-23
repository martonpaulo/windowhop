import CoreGraphics
import Foundation
import Synchronization
import Testing

@testable import WindowHopKit

/// Printable shortcut keys are labelled by the current keyboard layout; special
/// keys keep one canonical name; the stored binding stays the physical key
/// code. Every layout here is a fixture, so nothing depends on or changes the
/// machine's input sources.
@MainActor
struct ShortcutFormatterLayoutTests {
    /// A layout reduced to the keys a test needs; every other key has no character.
    private struct FixtureLayout: KeyLabelSource {
        let characters: [UInt16: String]
        let onQuery: (@Sendable (UInt16) -> Void)?

        init(_ characters: [UInt16: String], onQuery: (@Sendable (UInt16) -> Void)? = nil) {
            self.characters = characters
            self.onQuery = onQuery
        }

        func character(forKeyCode keyCode: UInt16) -> String? {
            onQuery?(keyCode)
            return characters[keyCode]
        }
    }

    /// Key codes a fixture layout was asked about, recorded from any thread.
    private final class QueryLog: Sendable {
        private let keys = Mutex<[UInt16]>([])
        var recorded: [UInt16] { keys.withLock { $0 } }
        func record(_ keyCode: UInt16) { keys.withLock { $0.append(keyCode) } }
    }

    private static let us = FixtureLayout([0: "a", 6: "z", 12: "q", 16: "y", 33: "["])
    private static let german = FixtureLayout([0: "a", 6: "y", 16: "z", 27: "ß", 33: "ü"])
    private static let french = FixtureLayout([0: "q", 6: "w", 12: "a", 16: "y", 33: "^"])

    private static let specialKeys: [Int64] = [
        KeyCode.tab, KeyCode.space, KeyCode.returnKey, KeyCode.escape, KeyCode.delete,
        KeyCode.forwardDelete, KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow,
        KeyCode.downArrow, 96,  // 96 is F5
    ]

    /// `ShortcutFormatter.keyLabels` is process-wide and other suites read it
    /// in parallel (XCTest restored it in tearDown). Each test that installs a
    /// layout runs on the main actor and restores the ANSI table before it
    /// returns, so no other test body ever sees a fixture layout.
    private static func restoreANSILabels() {
        ShortcutFormatter.keyLabels = ANSIKeyLabels()
    }

    private func labels(_ keyCodes: [Int64], under layout: KeyLabelSource) -> [String] {
        ShortcutFormatter.keyLabels = layout
        return keyCodes.map(ShortcutFormatter.keySymbol(for:))
    }

    @Test func printableKeysFollowTheLayout() {
        defer { Self.restoreANSILabels() }
        #expect(labels([0, 6, 16], under: Self.us) == ["A", "Z", "Y"])
        #expect(labels([6, 16], under: Self.german) == ["Y", "Z"])
        #expect(labels([0, 12], under: Self.french) == ["Q", "A"])
    }

    @Test func theStoredBindingIsThePhysicalKey() {
        defer { Self.restoreANSILabels() }
        let shortcut = PersistentShortcut(keyCode: 6, modifiers: [.maskAlternate])
        ShortcutFormatter.keyLabels = Self.us
        #expect(shortcut.displayString == "⌥Z")

        ShortcutFormatter.keyLabels = Self.german

        #expect(shortcut.displayString == "⌥Y")
        #expect(shortcut.keyCode == 6, "a layout change never rewrites the binding")
        #expect(shortcut.encoded == "\(CGEventFlags.maskAlternate.rawValue):6")
        #expect(shortcut.matches(keyCode: 6, flags: [.maskAlternate]))
    }

    @Test func deadKeyShowsItsOwnCharacter() {
        defer { Self.restoreANSILabels() }
        #expect(labels([33], under: Self.french) == ["^"])
    }

    @Test func specialKeysKeepCanonicalNamesUnderEveryLayout() {
        defer { Self.restoreANSILabels() }
        let queried = QueryLog()
        let recording = FixtureLayout([48: "x", 49: "y", 36: "z"]) { queried.record($0) }
        let canonical = Self.specialKeys.map(KeyCodeNames.name(for:))
        #expect(canonical == ["⇥", "Space", "↩", "⎋", "⌫", "⌦", "←", "→", "↑", "↓", "F5"])

        for layout: KeyLabelSource in [Self.us, Self.german, Self.french, recording] {
            #expect(labels(Self.specialKeys, under: layout) == canonical)
            #expect(
                Self.specialKeys.map(ShortcutFormatter.spokenKeyName(for:)) == [
                    "Tab", "Space", "Return", "Escape", "Delete", "Forward Delete",
                    "Left Arrow", "Right Arrow", "Up Arrow", "Down Arrow", "F5",
                ])
        }
        #expect(queried.recorded == [], "special keys never reach the layout")
    }

    @Test func untranslatableKeysFallBackToTheANSITable() {
        defer { Self.restoreANSILabels() }
        let empty = FixtureLayout([0: "", 1: "\u{10}", 2: " ", 3: "ab", 4: "\t"])
        #expect(
            labels([0, 1, 2, 3, 4, 5], under: empty) == ["A", "S", "D", "F", "H", "G"],
            "empty, control, whitespace, multi-character and missing results fall back")
    }

    @Test func outOfRangeKeyCodesNeverReachTheLayout() {
        defer { Self.restoreANSILabels() }
        let queried = QueryLog()
        let layout = FixtureLayout([:]) { queried.record($0) }

        #expect(labels([300, -1, 70_000], under: layout) == ["Key 300", "Key -1", "Key 70000"])
        #expect(queried.recorded == [300], "only a key code that fits UInt16 is translated")
    }

    @Test func multiScalarCharactersStayWhole() {
        defer { Self.restoreANSILabels() }
        let combining = "e\u{301}"  // one grapheme, two scalars
        let nonBMP = "\u{1D4B6}"  // one scalar, two UTF-16 units
        let layout = FixtureLayout([0: combining, 1: nonBMP])

        #expect(labels([0, 1], under: layout) == [combining.uppercased(), nonBMP])
    }

    @Test func uppercasingNeverSplitsACharacter() {
        defer { Self.restoreANSILabels() }
        #expect(labels([27], under: Self.german) == ["ß"], "not SS")
    }

    @Test func spokenStringsFollowTheSamePrintableRule() {
        defer { Self.restoreANSILabels() }
        ShortcutFormatter.keyLabels = Self.german
        let shortcut = PersistentShortcut(keyCode: 6, modifiers: [.maskAlternate])

        #expect(shortcut.spokenString == "Option Y")
        #expect(
            ShortcutFormatter.spokenChord(modifiers: .maskCommand, keyCode: KeyCode.tab) == "Command Tab")
    }

    @Test func printableCharacterIsTheLayoutsOwnForm() {
        defer { Self.restoreANSILabels() }
        ShortcutFormatter.keyLabels = Self.french
        #expect(ShortcutFormatter.printableCharacter(for: 12) == "a")
        #expect(ShortcutFormatter.printableCharacter(for: KeyCode.space) == nil)
        #expect(ShortcutFormatter.printableCharacter(for: 40) == nil, "no character, no guess")
    }

    @Test func defaultSourceIsTheANSITable() {
        #expect(ShortcutFormatter.keySymbol(for: 6) == "Z")
        #expect(ShortcutFormatter.keySymbol(for: 12) == "Q")
    }
}
