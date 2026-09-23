import Foundation
import Testing

@testable import WindowHopKit

struct SwitcherRevealDelayTests {
    @Test func presetsExposeNamedDurationsRatherThanRawMilliseconds() {
        #expect(SwitcherRevealDelay.off.duration == nil)
        #expect(SwitcherRevealDelay.milliseconds100.duration == 0.1)
        #expect(SwitcherRevealDelay.milliseconds200.duration == 0.2)
        #expect(SwitcherRevealDelay.milliseconds300.duration == 0.3)
        #expect(SwitcherRevealDelay.milliseconds500.duration == 0.5)
        #expect(
            SwitcherRevealDelay.allCases.map(\.displayName) == ["Off", "100 ms", "200 ms", "300 ms", "500 ms"])
    }

    @Test func heldSessionsWaitForTheConfiguredDelay() {
        for preset in SwitcherRevealDelay.allCases {
            #expect(preset.delay(for: .held) == preset.duration)
        }
    }

    @Test func offRevealsHeldSessionsImmediately() {
        #expect(SwitcherRevealDelay.off.delay(for: .held) == nil)
    }

    @Test func stickySessionsNeverWait() {
        // Open WindowHop was asked for explicitly: there is no quick tap to hide
        for preset in SwitcherRevealDelay.allCases {
            #expect(preset.delay(for: .sticky) == nil)
            #expect(preset.delay(for: .confirming) == nil)
            #expect(preset.delay(for: .inactive) == nil)
        }
    }

    @Test func theFirstTriggerOpensAHeldSessionThatWaits() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(Preferences.Defaults.switcherRevealDelay.delay(for: state.phase) == 0.1)
    }

    @Test func openWindowHopOpensAStickySessionThatDoesNotWait() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(Preferences.Defaults.switcherRevealDelay.delay(for: state.phase) == nil)
    }

    @Test func aQuickTapActivatesThePreviousWindowLikeASingleTrigger() {
        // releasing inside the delay goes through the same state transition as
        // a visible session, so the target is unchanged by the reveal delay
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.modifierReleased() == .activate(index: 1))
        #expect(state.phase == .inactive)
    }
}
