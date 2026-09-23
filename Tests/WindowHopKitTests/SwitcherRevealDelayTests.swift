import XCTest
@testable import WindowHopKit

final class SwitcherRevealDelayTests: XCTestCase {
    func testPresetsExposeNamedDurationsRatherThanRawMilliseconds() {
        XCTAssertNil(SwitcherRevealDelay.off.duration)
        XCTAssertEqual(SwitcherRevealDelay.milliseconds100.duration, 0.1)
        XCTAssertEqual(SwitcherRevealDelay.milliseconds200.duration, 0.2)
        XCTAssertEqual(SwitcherRevealDelay.milliseconds300.duration, 0.3)
        XCTAssertEqual(SwitcherRevealDelay.milliseconds500.duration, 0.5)
        XCTAssertEqual(SwitcherRevealDelay.allCases.map(\.displayName),
                       ["Off", "100 ms", "200 ms", "300 ms", "500 ms"])
    }

    func testHeldSessionsWaitForTheConfiguredDelay() {
        for preset in SwitcherRevealDelay.allCases {
            XCTAssertEqual(preset.delay(for: .held), preset.duration)
        }
    }

    func testOffRevealsHeldSessionsImmediately() {
        XCTAssertNil(SwitcherRevealDelay.off.delay(for: .held))
    }

    func testStickySessionsNeverWait() {
        // Open WindowHop was asked for explicitly: there is no quick tap to hide
        for preset in SwitcherRevealDelay.allCases {
            XCTAssertNil(preset.delay(for: .sticky))
            XCTAssertNil(preset.delay(for: .confirming))
            XCTAssertNil(preset.delay(for: .inactive))
        }
    }

    func testTheFirstTriggerOpensAHeldSessionThatWaits() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(Preferences.Defaults.switcherRevealDelay.delay(for: state.phase), 0.1)
    }

    func testOpenWindowHopOpensAStickySessionThatDoesNotWait() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertNil(Preferences.Defaults.switcherRevealDelay.delay(for: state.phase))
    }

    func testAQuickTapActivatesThePreviousWindowLikeASingleTrigger() {
        // releasing inside the delay goes through the same state transition as
        // a visible session, so the target is unchanged by the reveal delay
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.modifierReleased(), .activate(index: 1))
        XCTAssertEqual(state.phase, .inactive)
    }
}
