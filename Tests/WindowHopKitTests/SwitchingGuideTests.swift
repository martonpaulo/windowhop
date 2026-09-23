import CoreGraphics
import XCTest

@testable import WindowHopKit

/// The switching guide is the first thing a new user reads after granting
/// Accessibility. It must follow the shortcuts actually configured, and every
/// key label in it must be the one `ShortcutFormatter` produces.
final class SwitchingGuideTests: XCTestCase {
    private static let keyK: Int64 = 40

    private func guide(
        _ spec: ShortcutSpec = .commandTab,
        persistent: PersistentShortcut? = .optionTab,
        enabled: Bool = true
    ) -> SwitchingGuide {
        SwitchingGuide(switcherShortcut: spec, persistentShortcut: persistent, enabled: enabled)
    }

    func testEachSwitcherShortcutNamesItsOwnHoldModifier() {
        for spec in ShortcutSpec.allCases {
            let held = guide(spec).firstSteps[0]
            let glyph = ShortcutFormatter.modifierSymbols(spec.holdModifier)
            let spoken = ShortcutFormatter.spokenModifiers(spec.holdModifier)
            XCTAssertTrue(held.display.hasPrefix("Hold \(glyph) and press "), held.display)
            XCTAssertTrue(held.display.contains("Release \(glyph) to switch"), held.display)
            XCTAssertTrue(held.spoken.hasPrefix("Hold \(spoken) and press Tab"), held.spoken)
            XCTAssertTrue(held.spoken.contains("Release \(spoken) to switch"), held.spoken)
        }
    }

    func testHeldAndPersistentSessionsExplainDifferentConfirmations() {
        let steps = guide().firstSteps
        XCTAssertEqual(steps.count, 2)
        // held: releasing the modifier confirms
        XCTAssertTrue(steps[0].display.contains("Release"))
        // persistent: an explicit key confirms, and one cancels
        XCTAssertTrue(steps[1].spoken.contains("without holding a key"))
        XCTAssertTrue(steps[1].spoken.contains("Return or Space switches"))
        XCTAssertTrue(steps[1].spoken.contains("Escape cancels"))
    }

    func testCustomPersistentShortcutAppearsInBothForms() {
        let custom = PersistentShortcut(keyCode: Self.keyK, modifiers: [.maskControl, .maskAlternate])
        let persistent = guide(persistent: custom).firstSteps[1]
        XCTAssertTrue(persistent.display.hasPrefix("Press ⌃⌥K to open WindowHop"), persistent.display)
        XCTAssertTrue(
            persistent.spoken.hasPrefix("Press Control Option K to open WindowHop"),
            persistent.spoken)
    }

    func testUnassignedPersistentShortcutPointsToShortcuts() {
        let persistent = guide(persistent: nil).firstSteps[1]
        XCTAssertTrue(persistent.display.hasPrefix("Open WindowHop has no shortcut."))
        XCTAssertTrue(persistent.display.contains("Record one in Shortcuts"))
    }

    func testDisabledWindowHopHandsSwitchingToTheNativeSwitcher() {
        // whatever WindowHop's own shortcut is, the native switcher is ⌘⇥
        let steps = guide(.optionTab, enabled: false).firstSteps
        XCTAssertEqual(steps.map(\.display), ["WindowHop is off. ⌘⇥ opens the native app switcher."])
        XCTAssertEqual(
            steps.map(\.spoken),
            ["WindowHop is off. Command Tab opens the native app switcher."])
    }

    func testKeyReferenceDescribesTheShortcutsEvenWhenDisabled() {
        let enabled = guide(enabled: true).keyReference
        XCTAssertEqual(guide(enabled: false).keyReference, enabled)
        XCTAssertEqual(Array(enabled.prefix(2)), guide().firstSteps)
        XCTAssertTrue(enabled[2].display.contains("⌫ closes the selected window after you confirm"))
        XCTAssertTrue(enabled[2].spoken.contains("Delete closes the selected window"))
    }

    /// Every key glyph in the copy is one the formatter produces for a key the
    /// sentence is about, so a second representation of a key cannot creep in.
    func testEveryGlyphComesFromTheFormatter() {
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
                let reference = guide(spec, persistent: persistent).keyReference
                let expected =
                    [
                        ShortcutFormatter.modifierSymbols(spec.holdModifier),
                        ShortcutFormatter.keySymbol(for: KeyCode.tab),
                        ShortcutFormatter.modifierSymbols(.maskShift),
                        ShortcutFormatter.keySymbol(for: KeyCode.delete),
                    ]
                    + (persistent == nil
                        ? []
                        : [
                            ShortcutFormatter.keySymbol(for: KeyCode.returnKey),
                            ShortcutFormatter.keySymbol(for: KeyCode.escape),
                        ] + persistent!.displayString.map(String.init))
                let text = reference.map(\.display).joined(separator: " ")
                XCTAssertEqual(glyphs(in: text), glyphs(in: expected.joined()), text)
                // the spoken form names keys in words only
                XCTAssertTrue(glyphs(in: reference.map(\.spoken).joined()).isEmpty)
            }
        }
    }
}
