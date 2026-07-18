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
}
