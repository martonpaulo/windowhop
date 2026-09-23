import XCTest

@testable import WindowHopKit

/// Which captured Open WindowHop chords are accepted, rejected, or need
/// confirmation. Layouts and system shortcut lists are fixtures: nothing reads
/// or changes the machine's configuration.
final class ShortcutConflictsTests: XCTestCase {
    private struct FixtureLayout: KeyLabelSource {
        let characters: [UInt16: String]
        func character(forKeyCode keyCode: UInt16) -> String? { characters[keyCode] }
    }

    /// French AZERTY: key code 12 (US Q) types a, key code 0 (US A) types q,
    /// key code 13 (US W) types z, key code 6 (US Z) types w.
    private static let azerty = FixtureLayout(characters: [0: "q", 12: "a", 13: "z", 6: "w"])

    /// US ANSI key codes for the standard command characters.
    private static let usKeys: [String: Int64] = [
        "q": 12, "h": 4, ",": 43, "w": 13, "m": 46, "n": 45, "o": 31, "s": 1, "p": 35,
        "f": 3, "z": 6, "x": 7, "c": 8, "v": 9, "a": 0,
    ]

    private static let commandSpace = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand])

    override func tearDown() {
        ShortcutFormatter.keyLabels = ANSIKeyLabels()
        super.tearDown()
    }

    private func assess(
        _ shortcut: PersistentShortcut,
        switcher: ShortcutSpec = .commandTab,
        current: PersistentShortcut? = nil,
        system: [PersistentShortcut] = [],
        labels: KeyLabelSource = ANSIKeyLabels()
    ) -> PersistentShortcut.CaptureAssessment {
        shortcut.assessCapture(against: switcher, current: current, systemShortcuts: system, labels: labels)
    }

    func testEveryStandardCommandIsRejectedWithItsName() {
        for command in ShortcutConflicts.standardCommands {
            guard let keyCode = Self.usKeys[command.character] else {
                XCTFail("no US key for \(command.name)")
                continue
            }
            let shortcut = PersistentShortcut(keyCode: keyCode, modifiers: command.modifiers)

            XCTAssertEqual(
                assess(shortcut),
                .reject(
                    .standardApplicationCommand(
                        chord: shortcut.displayString,
                        command: command.name)),
                command.name)
        }
        XCTAssertEqual(
            PersistentShortcut.ValidationError
                .standardApplicationCommand(chord: "⌘Q", command: "Quit").explanation,
            "⌘Q is the Quit command in apps. Choose a combination that isn't a standard app command.")
    }

    func testRedoAndUndoAreDistinguishedByShift() {
        let undo = PersistentShortcut(keyCode: 6, modifiers: [.maskCommand])
        let redo = PersistentShortcut(keyCode: 6, modifiers: [.maskCommand, .maskShift])
        let optionZ = PersistentShortcut(keyCode: 6, modifiers: [.maskCommand, .maskAlternate])

        XCTAssertEqual(assess(undo), .reject(.standardApplicationCommand(chord: "⌘Z", command: "Undo")))
        XCTAssertEqual(assess(redo), .reject(.standardApplicationCommand(chord: "⇧⌘Z", command: "Redo")))
        XCTAssertEqual(assess(optionZ), .accept, "only the exact modifiers are a standard command")
    }

    func testCommandsAreMatchedByTheLayoutsCharacter() {
        ShortcutFormatter.keyLabels = Self.azerty
        let selectAll = PersistentShortcut(keyCode: 12, modifiers: [.maskCommand])
        let quit = PersistentShortcut(keyCode: 0, modifiers: [.maskCommand])

        XCTAssertEqual(
            assess(selectAll, labels: Self.azerty),
            .reject(.standardApplicationCommand(chord: "⌘A", command: "Select All")))
        XCTAssertEqual(
            assess(quit, labels: Self.azerty),
            .reject(.standardApplicationCommand(chord: "⌘Q", command: "Quit")))
        XCTAssertEqual(
            assess(PersistentShortcut(keyCode: 13, modifiers: [.maskCommand]), labels: Self.azerty),
            .reject(.standardApplicationCommand(chord: "⌘Z", command: "Undo")))
    }

    func testUntranslatedKeysFallBackToTheANSICharacter() {
        let noLayout = FixtureLayout(characters: [:])
        XCTAssertEqual(
            ShortcutConflicts.standardCommand(
                for: PersistentShortcut(keyCode: 12, modifiers: [.maskCommand]), labels: noLayout)?.name, "Quit")
    }

    func testForceQuitChordsAreReservedByMacOS() {
        for reserved in ShortcutConflicts.reservedByMacOS {
            XCTAssertEqual(
                assess(reserved, system: [reserved]),
                .reject(.reservedByMacOS(chord: reserved.displayString)))
        }
        XCTAssertEqual(ShortcutConflicts.reservedByMacOS.map(\.displayString), ["⌥⌘⎋", "⌥⇧⌘⎋", "⌃⌥⇧⌘⎋"])
        XCTAssertEqual(
            PersistentShortcut.ValidationError.reservedByMacOS(chord: "⌥⌘⎋").explanation,
            "⌥⌘⎋ is reserved by macOS. Choose a different combination.")
    }

    func testEnabledSystemShortcutNeedsConfirmation() {
        XCTAssertEqual(assess(Self.commandSpace, system: [Self.commandSpace]), .confirmSystemShortcut)
        XCTAssertEqual(assess(Self.commandSpace, system: []), .accept, "not enabled, not a conflict")
        let shifted = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(assess(shifted, system: [Self.commandSpace]), .accept, "exact chords only")
    }

    func testReRecordingTheStoredChordIsAccepted() {
        let quit = PersistentShortcut(keyCode: 12, modifiers: [.maskCommand])
        XCTAssertEqual(assess(quit, current: quit), .accept, "an existing choice is never blocked")
        XCTAssertEqual(
            assess(Self.commandSpace, current: Self.commandSpace, system: [Self.commandSpace]),
            .accept)
    }

    func testLoadTimeRulesStillComeFirst() {
        let optionTab = PersistentShortcut.optionTab
        XCTAssertEqual(assess(optionTab), .accept, "the ⌥Tab default is fine with ⌘Tab")
        XCTAssertEqual(
            assess(optionTab, switcher: .optionTab, current: optionTab),
            .reject(.conflictsWithSwitcherShortcut),
            "the current chord does not excuse a switcher conflict")
        XCTAssertEqual(
            assess(PersistentShortcut(keyCode: 12, modifiers: [.maskShift])),
            .reject(.needsModifier))
    }

    func testValidateStaysTheLoadRuleAndIgnoresNewConflicts() {
        let quit = PersistentShortcut(keyCode: 12, modifiers: [.maskCommand])
        XCTAssertNil(quit.validate(against: .commandTab), "a stored ⌘Q is not rejected on load")
    }

    func testSystemConfirmationCopyNamesTheChordAndWhereToChangeIt() {
        let copy = Self.commandSpace.systemShortcutConfirmation
        XCTAssertEqual(copy.title, "⌘Space is also a macOS shortcut")
        XCTAssertTrue(copy.message.contains("System Settings → Keyboard → Keyboard Shortcuts"))
    }
}
