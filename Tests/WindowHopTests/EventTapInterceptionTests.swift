import CoreGraphics
import XCTest
@testable import WindowHopCore

final class EventTapInterceptionTests: XCTestCase {
    func testCommandTabSequenceIsFullyConsumedAndReleasesOnModifierChange() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)

        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand),
            EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
        XCTAssertEqual(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand),
            .consume)
        XCTAssertEqual(
            state.decide(type: .flagsChanged, keyCode: 55, flags: []),
            EventTapDecision(disposition: .pass, input: .modifierReleased))
    }

    func testReverseAndRepeatedCyclingNeverLeaksToNativeSwitcher() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        let reverseFlags: CGEventFlags = [.maskCommand, .maskShift]

        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: reverseFlags),
            EventTapDecision(disposition: .consume, input: .trigger(backward: true)))
        XCTAssertEqual(state.decide(type: .keyUp, keyCode: KeyCode.tab,
                                    flags: reverseFlags), .consume)
        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand),
            EventTapDecision(disposition: .consume, input: .step(backward: false)))
        XCTAssertEqual(state.decide(type: .keyUp, keyCode: KeyCode.tab,
                                    flags: .maskCommand), .consume)
    }

    func testRapidSessionEndStillConsumesOwnedKeyUp() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
        state.mode = .watching

        XCTAssertEqual(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand),
            .consume)
        XCTAssertEqual(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand),
            .pass)
    }

    func testOnlyConfiguredChordIsInterceptedWhileWatching() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)

        XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.tab,
                                    flags: .maskControl), .pass)
        XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.comma,
                                    flags: .maskCommand), .pass)
        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate),
            EventTapDecision(disposition: .consume, input: .openPersistent))
    }

    func testStoppingResetsSuppressedReleasesAndInterception() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
        state.reset()

        XCTAssertEqual(state.mode, .off)
        XCTAssertTrue(state.suppressedKeyUps.isEmpty)
        XCTAssertEqual(state.decide(type: .keyUp, keyCode: KeyCode.tab,
                                    flags: .maskCommand), .pass)
    }

    // MARK: - Shortcut recording (#83)

    private func watchingState(recording: Bool) -> EventTapInterceptionState {
        EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab,
            isRecordingShortcut: recording)
    }

    /// Without the recording flag the tap owns both chords, so a keyDown the
    /// recorder waits for would never be delivered to the app.
    func testWatchingConsumesBothChordsWhenNotRecording() {
        var persistent = watchingState(recording: false)
        XCTAssertEqual(
            persistent.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate),
            EventTapDecision(disposition: .consume, input: .openPersistent))

        var held = watchingState(recording: false)
        XCTAssertEqual(
            held.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand),
            EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
    }

    func testRecordingPassesBothChordsWithoutOwningTheirRelease() {
        var state = watchingState(recording: true)

        for flags: CGEventFlags in [.maskAlternate, .maskCommand, [.maskCommand, .maskShift]] {
            XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: flags), .pass)
            XCTAssertEqual(state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: flags), .pass)
        }
        XCTAssertEqual(state.mode, .watching, "no session starts while recording")
        XCTAssertTrue(state.suppressedKeyUps.isEmpty, "nothing enters the key-up ledger")
    }

    func testReleaseOwnedBeforeRecordingIsStillConsumed() {
        var state = watchingState(recording: false)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
        state.mode = .watching
        state.isRecordingShortcut = true

        XCTAssertEqual(state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskAlternate),
                       .consume)
        XCTAssertTrue(state.suppressedKeyUps.isEmpty)
    }

    func testEndingRecordingRestoresInterception() {
        var state = watchingState(recording: true)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
        state.isRecordingShortcut = false

        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate),
            EventTapDecision(disposition: .consume, input: .openPersistent))
    }

    func testResetKeepsTheRecorderOwnedFlag() {
        var state = watchingState(recording: true)
        state.reset()
        state.mode = .watching

        XCTAssertTrue(state.isRecordingShortcut)
        XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand),
                       .pass)
    }

    func testFlagsChangedPassesWhetherOrNotRecording() {
        for recording in [false, true] {
            for mode: TapMode in [.off, .watching, .sessionHeld, .sessionSticky, .passthrough] {
                var state = watchingState(recording: recording)
                state.mode = mode
                for flags: CGEventFlags in [[], .maskCommand, .maskAlternate] {
                    XCTAssertEqual(
                        state.decide(type: .flagsChanged, keyCode: 55, flags: flags).disposition,
                        .pass, "flagsChanged is never consumed (\(mode), recording \(recording))")
                }
            }
        }
    }

    // MARK: - Session keys and foreign modifiers (#76)

    private struct Session {
        let name: String
        let mode: TapMode
        let holdModifier: CGEventFlags
        let persistentShortcut: PersistentShortcut
        let owner: CGEventFlags
        /// Whether a key carrying ⌃⌥ (the default VoiceOver modifiers) still
        /// belongs to the session.
        let ownsControlOption: Bool

        func state() -> EventTapInterceptionState {
            EventTapInterceptionState(mode: mode, holdModifier: holdModifier,
                                      persistentShortcut: persistentShortcut)
        }
    }

    private static let keyK: Int64 = 40

    private static let sessions = [
        Session(name: "held ⌘Tab", mode: .sessionHeld, holdModifier: .maskCommand,
                persistentShortcut: .optionTab, owner: .maskCommand, ownsControlOption: false),
        Session(name: "held ⌃Tab", mode: .sessionHeld, holdModifier: .maskControl,
                persistentShortcut: .optionTab, owner: .maskControl, ownsControlOption: false),
        Session(name: "sticky ⌥Tab", mode: .sessionSticky, holdModifier: .maskCommand,
                persistentShortcut: .optionTab, owner: .maskAlternate, ownsControlOption: false),
        // documented overlap: an Open WindowHop chord made of ⌃⌥ owns ⌃⌥ keys
        Session(name: "sticky ⌃⌥K", mode: .sessionSticky, holdModifier: .maskCommand,
                persistentShortcut: PersistentShortcut(keyCode: keyK,
                                                       modifiers: [.maskControl, .maskAlternate]),
                owner: [.maskControl, .maskAlternate], ownsControlOption: true),
    ]

    /// Every key a session handles, with the input it produces when matched.
    private static func sessionKeys(sticky: Bool, flags: CGEventFlags)
        -> [(name: String, keyCode: Int64, input: SwitcherInputEvent?)] {
        [
            ("Tab", KeyCode.tab, .step(backward: flags.contains(.maskShift))),
            ("Escape", KeyCode.escape, .escape),
            ("Return", KeyCode.returnKey, .returnKey),
            ("Enter", KeyCode.keypadEnter, .returnKey),
            ("Space", KeyCode.space, sticky ? .spaceKey : nil),
            ("Up", KeyCode.upArrow, .arrow(.up)),
            ("Down", KeyCode.downArrow, .arrow(.down)),
            ("Left", KeyCode.leftArrow, .arrow(.left)),
            ("Right", KeyCode.rightArrow, .arrow(.right)),
            ("Delete", KeyCode.delete, .deleteKey),
            ("Forward Delete", KeyCode.forwardDelete, .deleteKey),
        ]
    }

    func testSessionKeyDispositionMatrix() {
        let controlOption: CGEventFlags = [.maskControl, .maskAlternate]
        for session in Self.sessions {
            let variants: [(name: String, flags: CGEventFlags, owned: Bool)] = [
                ("plain", [], true),
                ("shift", .maskShift, true),
                ("owner", session.owner, true),
                ("owner+shift", session.owner.union(.maskShift), true),
                ("⌃⌥", controlOption, session.ownsControlOption),
                ("⌃⌥⇧", controlOption.union(.maskShift), session.ownsControlOption),
                ("caps lock", .maskAlphaShift, true),
                ("fn+keypad", [.maskSecondaryFn, .maskNumericPad], true),
            ]
            let sticky = session.mode == .sessionSticky
            for variant in variants {
                for key in Self.sessionKeys(sticky: sticky, flags: variant.flags) {
                    let label = "\(session.name), \(variant.name) \(key.name)"
                    var state = session.state()
                    let down = state.decide(type: .keyDown, keyCode: key.keyCode, flags: variant.flags)
                    let up = state.decide(type: .keyUp, keyCode: key.keyCode, flags: variant.flags)
                    if session.persistentShortcut.matches(keyCode: key.keyCode, flags: variant.flags) {
                        // re-pressing the Open WindowHop chord is swallowed, not an input
                        XCTAssertEqual(down, .consume, label)
                        XCTAssertEqual(up, .consume, label)
                    } else if variant.owned, let input = key.input {
                        XCTAssertEqual(down, EventTapDecision(disposition: .consume, input: input), label)
                        XCTAssertEqual(up, .consume, label)
                    } else {
                        XCTAssertEqual(down, .pass, label)
                        XCTAssertEqual(up, .pass, label)
                    }
                    XCTAssertTrue(state.suppressedKeyUps.isEmpty, label)
                    XCTAssertEqual(state.mode, session.mode, "\(label): the session stays open")
                }
                var state = session.state()
                XCTAssertEqual(state.decide(type: .flagsChanged, keyCode: 59,
                                            flags: variant.flags).disposition,
                               .pass, "\(session.name): flagsChanged \(variant.name) passes")
            }
        }
    }

    func testVoiceOverChordsPassInDefaultSessions() {
        var held = Self.sessions[0].state()
        XCTAssertEqual(held.decide(type: .keyDown, keyCode: KeyCode.rightArrow,
                                   flags: [.maskControl, .maskAlternate]), .pass)
        XCTAssertEqual(held.decide(type: .keyDown, keyCode: KeyCode.rightArrow,
                                   flags: .maskCommand),
                       EventTapDecision(disposition: .consume, input: .arrow(.right)),
                       "held ⌘ + arrow still navigates")

        var sticky = Self.sessions[2].state()
        XCTAssertEqual(sticky.decide(type: .keyDown, keyCode: KeyCode.space,
                                     flags: [.maskControl, .maskAlternate]), .pass)
        XCTAssertEqual(sticky.decide(type: .keyDown, keyCode: KeyCode.space, flags: []),
                       EventTapDecision(disposition: .consume, input: .spaceKey))
    }

    func testSwitcherTriggerStepsInAStickySession() {
        var state = Self.sessions[2].state()
        XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand),
                       EventTapDecision(disposition: .consume, input: .step(backward: false)))
        XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.tab,
                                    flags: [.maskCommand, .maskShift]),
                       EventTapDecision(disposition: .consume, input: .step(backward: true)))
        XCTAssertEqual(state.decide(type: .keyDown, keyCode: KeyCode.tab,
                                    flags: [.maskCommand, .maskControl]), .pass)
    }

    func testSettingsChordRequiresCommandAndNoForeignModifier() {
        let settings = EventTapDecision(disposition: .consume, input: .openSettings)
        var held = Self.sessions[0].state()
        XCTAssertEqual(held.decide(type: .keyDown, keyCode: KeyCode.comma, flags: .maskCommand),
                       settings)

        let cases: [(CGEventFlags, EventTapDecision)] = [
            (.maskCommand, settings),
            ([.maskCommand, .maskAlternate], settings),
            ([.maskCommand, .maskShift], settings),
            ([.maskCommand, .maskControl], .pass),
            ([.maskControl, .maskAlternate], .pass),
            ([], .pass),
        ]
        for (flags, expected) in cases {
            var sticky = Self.sessions[2].state()
            XCTAssertEqual(sticky.decide(type: .keyDown, keyCode: KeyCode.comma, flags: flags),
                           expected, "sticky ⌥Tab, comma with \(flags.rawValue)")
        }
    }
}
