import Foundation
import Testing
import WindowHopTestSupport

@testable import WindowHopKit

@MainActor
struct SwitcherStateTests {
    // MARK: - Opening

    @Test func triggerWithZeroWindowsDoesNothing() {
        var state = SwitcherState()
        #expect(state.trigger(backward: false, itemCount: 0) == .none)
        #expect(state.phase == .inactive)
    }

    @Test func triggerWithOneWindowSelectsIt() {
        var state = SwitcherState()
        #expect(state.trigger(backward: false, itemCount: 1) == .show(selectedIndex: 0))
        #expect(state.phase == .held)
    }

    @Test func triggerSelectsPreviousWindow() {
        var state = SwitcherState()
        #expect(state.trigger(backward: false, itemCount: 5) == .show(selectedIndex: 1))
    }

    @Test func backwardTriggerSelectsLastWindow() {
        var state = SwitcherState()
        #expect(state.trigger(backward: true, itemCount: 5) == .show(selectedIndex: 4))
    }

    // MARK: - Cycling and wrapping

    @Test func forwardCyclingWraps() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)  // selection 1
        #expect(state.step(backward: false) == .select(index: 2))
        #expect(state.step(backward: false) == .select(index: 0))
        #expect(state.step(backward: false) == .select(index: 1))
    }

    @Test func backwardCyclingWraps() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)  // selection 1
        #expect(state.step(backward: true) == .select(index: 0))
        #expect(state.step(backward: true) == .select(index: 2))
    }

    @Test func shiftMayBePressedAndReleasedMidSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4)  // 1
        _ = state.step(backward: false)  // 2
        _ = state.step(backward: true)  // 1
        #expect(state.step(backward: false) == .select(index: 2))
    }

    @Test func arrowDirections() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4)  // 1
        #expect(state.arrow(.down) == .select(index: 2))
        #expect(state.arrow(.up) == .select(index: 1))
        #expect(state.arrow(.right) == .select(index: 2))
        #expect(state.arrow(.left) == .select(index: 1))
    }

    // MARK: - Ending the session

    @Test func modifierReleaseActivatesSelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.step(backward: false)
        #expect(state.modifierReleased() == .activate(index: 2))
        #expect(state.phase == .inactive)
    }

    @Test func escapeCancelsWithoutActivating() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.escape() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func returnActivatesSelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.returnKey() == .activate(index: 1))
    }

    @Test func clickActivatesClickedItem() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.itemClicked(index: 2) == .activate(index: 2))
        #expect(state.phase == .inactive)
    }

    @Test func clickOutsideValidRangeIsIgnored() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.itemClicked(index: 7) == .none)
        #expect(state.phase == .held)
    }

    @Test func outsideClickCancels() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.outsideClick() == .cancel)
    }

    @Test func eventsWhileInactiveAreIgnored() {
        var state = SwitcherState()
        #expect(state.modifierReleased() == .none)
        #expect(state.escape() == .none)
        #expect(state.returnKey() == .none)
        #expect(state.step(backward: false) == .none)
        #expect(state.deleteKey() == .none)
    }

    // MARK: - Close confirmation

    @Test func deleteRequestsCloseAndSuspendsSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.deleteKey() == .requestClose(index: 1))
        #expect(state.phase == .confirming)
    }

    @Test func modifierReleaseDuringConfirmationDoesNotActivate() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        #expect(state.modifierReleased() == .none)
        #expect(state.phase == .confirming)
    }

    @Test func triggerDuringConfirmationIsIgnored() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        #expect(state.trigger(backward: false, itemCount: 3) == .none)
    }

    @Test func sessionContinuesStickyAfterConfirmation() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        #expect(state.confirmationFinished() == .none)
        #expect(state.phase == .sticky)
        // navigation still works without a held modifier
        #expect(state.step(backward: false) == .select(index: 2))
        #expect(state.modifierReleased() == .none)
        #expect(state.returnKey() == .activate(index: 2))
    }

    // MARK: - List changes while open

    @Test func windowClosingKeepsNearbySelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4)
        _ = state.step(backward: false)  // selection 2
        #expect(state.listChanged(itemCount: 3, preferredIndex: 2) == .select(index: 2))
        #expect(state.listChanged(itemCount: 2, preferredIndex: 2) == .select(index: 1))
    }

    @Test func listBecomingEmptyCancels() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 2)
        #expect(state.listChanged(itemCount: 0, preferredIndex: nil) == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func resetEndsSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        state.reset()
        #expect(state.phase == .inactive)
        #expect(state.modifierReleased() == .none)
    }
}

extension SwitcherStateTests {
    // MARK: - Hover close routing and appearance preference

    @Test func hoverCloseRequestTargetsExplicitIndexWithoutMovingSelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4)  // selection 1
        #expect(state.closeRequested(index: 3) == .requestClose(index: 3))
        #expect(state.phase == .confirming)
        // cancelling restores the exact previous selection
        _ = state.confirmationFinished()
        #expect(state.selectedIndex == 1)
    }

    @Test func hoverCloseRequestOutOfRangeIsIgnored() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 2)
        #expect(state.closeRequested(index: 5) == .none)
        #expect(state.phase == .held)
    }

    @Test func deleteRoutesThroughTheSameCloseRequestFlow() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.deleteKey() == .requestClose(index: 1))
        #expect(state.phase == .confirming)
    }

    // MARK: - Teardown and session identity

    @Test func teardownFromHeldCancels() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.teardown() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func teardownFromHeldCloseConfirmationCancels() {
        // escape belongs to the dialog while confirming; disabling must not
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        #expect(state.escape() == .none)
        #expect(state.phase == .confirming)
        #expect(state.teardown() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func teardownFromStickyCloseConfirmationCancels() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        _ = state.deleteKey()
        #expect(state.teardown() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func teardownWhileInactiveDoesNothing() {
        var state = SwitcherState()
        #expect(state.teardown() == .none)
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.teardown()
        #expect(state.teardown() == .none)
    }

    @Test func nextSessionAfterTeardownOpensNormally() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        _ = state.teardown()
        #expect(state.trigger(backward: false, itemCount: 3) == .show(selectedIndex: 1))
        #expect(state.phase == .held)
        _ = state.teardown()
        #expect(state.openPersistent(itemCount: 3) == .show(selectedIndex: 1))
        #expect(state.phase == .sticky)
    }

    @Test func sessionIDChangesPerSessionOnly() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        let first = state.sessionID
        _ = state.trigger(backward: false, itemCount: 3)  // step, same session
        _ = state.arrow(.right)
        _ = state.deleteKey()
        _ = state.confirmationFinished()
        #expect(state.sessionID == first)
        _ = state.escape()
        #expect(state.sessionID == first)
        _ = state.trigger(backward: false, itemCount: 3)
        #expect(state.sessionID != first)
        let second = state.sessionID
        _ = state.returnKey()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.sessionID != second)
        #expect(state.sessionID != first)
    }

    @Test func staleHeldConfirmationIsNotRevivedByANewSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        let stale = state.sessionID
        #expect(state.isConfirming(sessionID: stale))
        _ = state.teardown()
        #expect(!state.isConfirming(sessionID: stale))
        // a new held session reaches its own confirmation before the old callback drains
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        #expect(!state.isConfirming(sessionID: stale))
        #expect(state.isConfirming(sessionID: state.sessionID))
    }

    @Test func appearanceModeDefaultsToAppIcons() throws {
        let suite = try TestDefaults()
        defer { suite.remove() }
        let defaults = suite.defaults
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.appearanceMode == .appIcons)
        preferences.appearanceMode = .windowPreviews
        #expect(preferences.appearanceMode == .windowPreviews)
        defaults.set("garbage", forKey: Preferences.Key.appearanceMode.rawValue)
        #expect(Preferences(defaults: defaults).appearanceMode == .appIcons)
    }
}
