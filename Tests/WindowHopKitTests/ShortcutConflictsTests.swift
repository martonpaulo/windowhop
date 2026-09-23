import Foundation
import Testing

@testable import WindowHopKit

/// Which captured Open WindowHop chords are accepted, rejected, or need
/// confirmation. Layouts and system shortcut lists are fixtures: nothing reads
/// or changes the machine's configuration.
@MainActor
struct ShortcutConflictsTests {
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

    /// `ShortcutFormatter.keyLabels` is process-wide and other suites read it
    /// in parallel (XCTest restored it in tearDown). Each test that installs a
    /// layout runs on the main actor and restores the ANSI table before it
    /// returns, so no other test body ever sees a fixture layout.
    private static func restoreANSILabels() {
        ShortcutFormatter.keyLabels = ANSIKeyLabels()
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

    @Test func everyStandardCommandIsRejectedWithItsName() {
        for command in ShortcutConflicts.standardCommands {
            guard let keyCode = Self.usKeys[command.character] else {
                Issue.record("no US key for \(command.name)")
                continue
            }
            let shortcut = PersistentShortcut(keyCode: keyCode, modifiers: command.modifiers)

            #expect(
                assess(shortcut)
                    == .reject(
                        .standardApplicationCommand(
                            chord: shortcut.displayString,
                            command: command.name)), "\(command.name)")
        }
        #expect(
            PersistentShortcut.ValidationError
                .standardApplicationCommand(chord: "⌘Q", command: "Quit").explanation
                == "⌘Q is the Quit command in apps. Choose a combination that isn't a standard app command.")
    }

    @Test func redoAndUndoAreDistinguishedByShift() {
        let undo = PersistentShortcut(keyCode: 6, modifiers: [.maskCommand])
        let redo = PersistentShortcut(keyCode: 6, modifiers: [.maskCommand, .maskShift])
        let optionZ = PersistentShortcut(keyCode: 6, modifiers: [.maskCommand, .maskAlternate])

        #expect(assess(undo) == .reject(.standardApplicationCommand(chord: "⌘Z", command: "Undo")))
        #expect(assess(redo) == .reject(.standardApplicationCommand(chord: "⇧⌘Z", command: "Redo")))
        #expect(assess(optionZ) == .accept, "only the exact modifiers are a standard command")
    }

    @Test func commandsAreMatchedByTheLayoutsCharacter() {
        defer { Self.restoreANSILabels() }
        ShortcutFormatter.keyLabels = Self.azerty
        let selectAll = PersistentShortcut(keyCode: 12, modifiers: [.maskCommand])
        let quit = PersistentShortcut(keyCode: 0, modifiers: [.maskCommand])

        #expect(
            assess(selectAll, labels: Self.azerty)
                == .reject(.standardApplicationCommand(chord: "⌘A", command: "Select All")))
        #expect(
            assess(quit, labels: Self.azerty) == .reject(.standardApplicationCommand(chord: "⌘Q", command: "Quit")))
        #expect(
            assess(PersistentShortcut(keyCode: 13, modifiers: [.maskCommand]), labels: Self.azerty)
                == .reject(.standardApplicationCommand(chord: "⌘Z", command: "Undo")))
    }

    @Test func untranslatedKeysFallBackToTheANSICharacter() {
        let noLayout = FixtureLayout(characters: [:])
        #expect(
            ShortcutConflicts.standardCommand(
                for: PersistentShortcut(keyCode: 12, modifiers: [.maskCommand]), labels: noLayout)?.name == "Quit")
    }

    @Test func forceQuitChordsAreReservedByMacOS() {
        for reserved in ShortcutConflicts.reservedByMacOS {
            #expect(
                assess(reserved, system: [reserved]) == .reject(.reservedByMacOS(chord: reserved.displayString)))
        }
        #expect(ShortcutConflicts.reservedByMacOS.map(\.displayString) == ["⌥⌘⎋", "⌥⇧⌘⎋", "⌃⌥⇧⌘⎋"])
        #expect(
            PersistentShortcut.ValidationError.reservedByMacOS(chord: "⌥⌘⎋").explanation
                == "⌥⌘⎋ is reserved by macOS. Choose a different combination.")
    }

    @Test func enabledSystemShortcutNeedsConfirmation() {
        #expect(assess(Self.commandSpace, system: [Self.commandSpace]) == .confirmSystemShortcut)
        #expect(assess(Self.commandSpace, system: []) == .accept, "not enabled, not a conflict")
        let shifted = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand, .maskShift])
        #expect(assess(shifted, system: [Self.commandSpace]) == .accept, "exact chords only")
    }

    @Test func reRecordingTheStoredChordIsAccepted() {
        let quit = PersistentShortcut(keyCode: 12, modifiers: [.maskCommand])
        #expect(assess(quit, current: quit) == .accept, "an existing choice is never blocked")
        #expect(
            assess(Self.commandSpace, current: Self.commandSpace, system: [Self.commandSpace]) == .accept)
    }

    @Test func loadTimeRulesStillComeFirst() {
        let optionTab = PersistentShortcut.optionTab
        #expect(assess(optionTab) == .accept, "the ⌥Tab default is fine with ⌘Tab")
        #expect(
            assess(optionTab, switcher: .optionTab, current: optionTab) == .reject(.conflictsWithSwitcherShortcut),
            "the current chord does not excuse a switcher conflict")
        #expect(
            assess(PersistentShortcut(keyCode: 12, modifiers: [.maskShift])) == .reject(.needsModifier))
    }

    @Test func validateStaysTheLoadRuleAndIgnoresNewConflicts() {
        let quit = PersistentShortcut(keyCode: 12, modifiers: [.maskCommand])
        #expect(quit.validate(against: .commandTab) == nil, "a stored ⌘Q is not rejected on load")
    }

    @Test func systemConfirmationCopyNamesTheChordAndWhereToChangeIt() {
        let copy = Self.commandSpace.systemShortcutConfirmation
        #expect(copy.title == "⌘Space is also a macOS shortcut")
        #expect(copy.message.contains("System Settings → Keyboard → Keyboard Shortcuts"))
    }
}
