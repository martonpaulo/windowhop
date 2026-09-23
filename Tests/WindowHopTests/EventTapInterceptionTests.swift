import CoreGraphics
import Foundation
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

struct EventTapInterceptionTests {
    @Test func commandTabSequenceIsFullyConsumedAndReleasesOnModifierChange() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)

        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
                == EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand) == .consume)
        #expect(
            state.decide(type: .flagsChanged, keyCode: 55, flags: [])
                == EventTapDecision(disposition: .pass, input: .modifierReleased))
    }

    @Test func reverseAndRepeatedCyclingNeverLeaksToNativeSwitcher() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        let reverseFlags: CGEventFlags = [.maskCommand, .maskShift]

        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: reverseFlags)
                == EventTapDecision(disposition: .consume, input: .trigger(backward: true)))
        #expect(
            state.decide(
                type: .keyUp, keyCode: KeyCode.tab,
                flags: reverseFlags) == .consume)
        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
                == EventTapDecision(disposition: .consume, input: .step(backward: false)))
        #expect(
            state.decide(
                type: .keyUp, keyCode: KeyCode.tab,
                flags: .maskCommand) == .consume)
    }

    @Test func rapidSessionEndStillConsumesOwnedKeyUp() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
        state.mode = .watching

        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand) == .consume)
        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand) == .pass)
    }

    @Test func onlyConfiguredChordIsInterceptedWhileWatching() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)

        #expect(
            state.decide(
                type: .keyDown, keyCode: KeyCode.tab,
                flags: .maskControl) == .pass)
        #expect(
            state.decide(
                type: .keyDown, keyCode: KeyCode.comma,
                flags: .maskCommand) == .pass)
        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
                == EventTapDecision(disposition: .consume, input: .openPersistent))
    }

    @Test func stoppingResetsSuppressedReleasesAndInterception() {
        var state = EventTapInterceptionState(
            mode: .watching,
            holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
        state.reset()

        #expect(state.mode == .off)
        #expect(state.suppressedKeyUps.isEmpty)
        #expect(
            state.decide(
                type: .keyUp, keyCode: KeyCode.tab,
                flags: .maskCommand) == .pass)
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
    @Test func watchingConsumesBothChordsWhenNotRecording() {
        var persistent = watchingState(recording: false)
        #expect(
            persistent.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
                == EventTapDecision(disposition: .consume, input: .openPersistent))

        var held = watchingState(recording: false)
        #expect(
            held.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
                == EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
    }

    @Test func recordingPassesBothChordsWithoutOwningTheirRelease() {
        var state = watchingState(recording: true)

        for flags: CGEventFlags in [.maskAlternate, .maskCommand, [.maskCommand, .maskShift]] {
            #expect(state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: flags) == .pass)
            #expect(state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: flags) == .pass)
        }
        #expect(state.mode == .watching, "no session starts while recording")
        #expect(state.suppressedKeyUps.isEmpty, "nothing enters the key-up ledger")
    }

    @Test func releaseOwnedBeforeRecordingIsStillConsumed() {
        var state = watchingState(recording: false)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
        state.mode = .watching
        state.isRecordingShortcut = true

        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskAlternate) == .consume)
        #expect(state.suppressedKeyUps.isEmpty)
    }

    @Test func endingRecordingRestoresInterception() {
        var state = watchingState(recording: true)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
        state.isRecordingShortcut = false

        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
                == EventTapDecision(disposition: .consume, input: .openPersistent))
    }

    @Test func resetKeepsTheRecorderOwnedFlag() {
        var state = watchingState(recording: true)
        state.reset()
        state.mode = .watching

        #expect(state.isRecordingShortcut)
        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand) == .pass)
    }

    @Test func flagsChangedPassesWhetherOrNotRecording() {
        for recording in [false, true] {
            for mode: TapMode in [.off, .watching, .sessionHeld, .sessionSticky, .passthrough] {
                var state = watchingState(recording: recording)
                state.mode = mode
                for flags: CGEventFlags in [[], .maskCommand, .maskAlternate] {
                    #expect(
                        state.decide(type: .flagsChanged, keyCode: 55, flags: flags).disposition == .pass,
                        "flagsChanged is never consumed (\(mode), recording \(recording))")
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
            EventTapInterceptionState(
                mode: mode, holdModifier: holdModifier,
                persistentShortcut: persistentShortcut)
        }
    }

    private static let keyK: Int64 = 40

    private static let sessions = [
        Session(
            name: "held ⌘Tab", mode: .sessionHeld, holdModifier: .maskCommand,
            persistentShortcut: .optionTab, owner: .maskCommand, ownsControlOption: false),
        Session(
            name: "held ⌃Tab", mode: .sessionHeld, holdModifier: .maskControl,
            persistentShortcut: .optionTab, owner: .maskControl, ownsControlOption: false),
        Session(
            name: "sticky ⌥Tab", mode: .sessionSticky, holdModifier: .maskCommand,
            persistentShortcut: .optionTab, owner: .maskAlternate, ownsControlOption: false),
        // documented overlap: an Open WindowHop chord made of ⌃⌥ owns ⌃⌥ keys
        Session(
            name: "sticky ⌃⌥K", mode: .sessionSticky, holdModifier: .maskCommand,
            persistentShortcut: PersistentShortcut(
                keyCode: keyK,
                modifiers: [.maskControl, .maskAlternate]),
            owner: [.maskControl, .maskAlternate], ownsControlOption: true),
    ]

    /// Every key a session handles, with the input it produces when matched.
    private static func sessionKeys(sticky: Bool, flags: CGEventFlags)
        -> [(name: String, keyCode: Int64, input: SwitcherInputEvent?)]
    {
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

    @Test func sessionKeyDispositionMatrix() {
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
                        #expect(down == .consume, "\(label)")
                        #expect(up == .consume, "\(label)")
                    } else if variant.owned, let input = key.input {
                        #expect(down == EventTapDecision(disposition: .consume, input: input), "\(label)")
                        #expect(up == .consume, "\(label)")
                    } else {
                        #expect(down == .pass, "\(label)")
                        #expect(up == .pass, "\(label)")
                    }
                    #expect(state.suppressedKeyUps.isEmpty, "\(label)")
                    #expect(state.mode == session.mode, "\(label): the session stays open")
                }
                var state = session.state()
                #expect(
                    state.decide(
                        type: .flagsChanged, keyCode: 59,
                        flags: variant.flags
                    ).disposition == .pass, "\(session.name): flagsChanged \(variant.name) passes")
            }
        }
    }

    @Test func voiceOverChordsPassInDefaultSessions() {
        var held = Self.sessions[0].state()
        #expect(
            held.decide(
                type: .keyDown, keyCode: KeyCode.rightArrow,
                flags: [.maskControl, .maskAlternate]) == .pass)
        #expect(
            held.decide(
                type: .keyDown, keyCode: KeyCode.rightArrow,
                flags: .maskCommand) == EventTapDecision(disposition: .consume, input: .arrow(.right)),
            "held ⌘ + arrow still navigates")

        var sticky = Self.sessions[2].state()
        #expect(
            sticky.decide(
                type: .keyDown, keyCode: KeyCode.space,
                flags: [.maskControl, .maskAlternate]) == .pass)
        #expect(
            sticky.decide(type: .keyDown, keyCode: KeyCode.space, flags: [])
                == EventTapDecision(disposition: .consume, input: .spaceKey))
    }

    @Test func switcherTriggerStepsInAStickySession() {
        var state = Self.sessions[2].state()
        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
                == EventTapDecision(disposition: .consume, input: .step(backward: false)))
        #expect(
            state.decide(
                type: .keyDown, keyCode: KeyCode.tab,
                flags: [.maskCommand, .maskShift])
                == EventTapDecision(disposition: .consume, input: .step(backward: true)))
        #expect(
            state.decide(
                type: .keyDown, keyCode: KeyCode.tab,
                flags: [.maskCommand, .maskControl]) == .pass)
    }

    @Test func settingsChordRequiresCommandAndNoForeignModifier() {
        let settings = EventTapDecision(disposition: .consume, input: .openSettings)
        var held = Self.sessions[0].state()
        #expect(
            held.decide(type: .keyDown, keyCode: KeyCode.comma, flags: .maskCommand) == settings)

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
            #expect(
                sticky.decide(type: .keyDown, keyCode: KeyCode.comma, flags: flags) == expected,
                "sticky ⌥Tab, comma with \(flags.rawValue)")
        }
    }

    // MARK: - Key-up ownership after a tap interruption (#84)
    //
    // While the tap is disabled (timeout, user input, or sleep before the wake re-arm),
    // events bypass it. A missed delivery is modelled by not feeding that event.

    /// Opens a session with Tab plus `flags` and loses the owned Tab key-up.
    private func missedOwnedTabKeyUp(openedWith flags: CGEventFlags) -> EventTapInterceptionState {
        var state = watchingState(recording: false)
        _ = state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: flags)
        #expect(state.suppressedKeyUps == [KeyCode.tab])
        return state
    }

    @Test func missedHeldKeyUpHealsAtTheNextPlainPress() {
        var state = missedOwnedTabKeyUp(openedWith: .maskCommand)
        #expect(state.mode == .sessionHeld)
        state.mode = .watching  // the held session ended

        #expect(state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: []) == .pass)
        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: []) == .pass,
            "a plain Tab release belongs to the app that got its key-down")
        #expect(state.suppressedKeyUps.isEmpty)
    }

    @Test func missedStickyKeyUpHealsAtTheNextPlainPress() {
        var state = missedOwnedTabKeyUp(openedWith: .maskAlternate)
        #expect(state.mode == .sessionSticky)
        state.mode = .watching  // the sticky session ended with Return

        #expect(state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: []) == .pass)
        #expect(state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: []) == .pass)
        #expect(state.suppressedKeyUps.isEmpty)
    }

    @Test func missedKeyUpDoesNotSwallowTheNativeCommandTabRelease() {
        var state = missedOwnedTabKeyUp(openedWith: .maskCommand)
        state.mode = .off  // switcher disabled or permission lost

        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand) == .pass)
        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand) == .pass,
            "the native switcher gets both halves of ⌘Tab")
    }

    @Test func missedKeyUpInsideAHeldSessionStillOwnsTheNextPair() {
        var state = missedOwnedTabKeyUp(openedWith: .maskCommand)

        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskCommand)
                == EventTapDecision(disposition: .consume, input: .step(backward: false)))
        state.mode = .watching  // modifier released between the halves
        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.tab, flags: .maskCommand) == .consume,
            "no orphaned Tab release reaches the native switcher")
        #expect(state.suppressedKeyUps.isEmpty)
    }

    @Test func releaseOfARepeatThatPassedAfterTheSessionEndedPasses() {
        var state = EventTapInterceptionState(
            mode: .sessionHeld, holdModifier: .maskCommand,
            persistentShortcut: .optionTab)
        #expect(
            state.decide(type: .keyDown, keyCode: KeyCode.rightArrow, flags: .maskCommand)
                == EventTapDecision(disposition: .consume, input: .arrow(.right)))
        state.mode = .watching
        // autorepeat continues after the session ended, and the app receives it
        #expect(state.decide(type: .keyDown, keyCode: KeyCode.rightArrow, flags: []) == .pass)
        #expect(
            state.decide(type: .keyUp, keyCode: KeyCode.rightArrow, flags: []) == .pass,
            "the app that received the repeats also receives the release")
    }

    @Test func anotherKeysPressLeavesOwnershipAlone() {
        var state = missedOwnedTabKeyUp(openedWith: .maskCommand)
        state.mode = .watching

        #expect(state.decide(type: .keyDown, keyCode: KeyCode.escape, flags: []) == .pass)
        #expect(state.suppressedKeyUps == [KeyCode.tab])
    }

    /// Loop re-enables only after a timeout (#36 survey); WindowHop recovers from both.
    @Test func bothTapDisableReasonsReEnableTheTap() {
        #expect(EventTap.reEnablesTap(after: .tapDisabledByTimeout))
        #expect(EventTap.reEnablesTap(after: .tapDisabledByUserInput))
        for type: CGEventType in [.keyDown, .keyUp, .flagsChanged] {
            #expect(!EventTap.reEnablesTap(after: type))
        }
    }
}
