import Foundation
import Testing

@testable import WindowHopKit

struct PersistentSessionTests {
    @Test func openSelectsPreviousWindow() {
        var state = SwitcherState()
        #expect(state.openPersistent(itemCount: 4) == .show(selectedIndex: 1))
        #expect(state.phase == .sticky)
    }

    @Test func openWithZeroWindowsDoesNothing() {
        var state = SwitcherState()
        #expect(state.openPersistent(itemCount: 0) == .none)
        #expect(state.phase == .inactive)
    }

    @Test func openWithOneWindowSelectsIt() {
        var state = SwitcherState()
        #expect(state.openPersistent(itemCount: 1) == .show(selectedIndex: 0))
    }

    @Test func modifierReleaseDoesNotCloseOrActivate() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.modifierReleased() == .none)
        #expect(state.phase == .sticky)
    }

    @Test func navigationWorksWithoutHeldModifier() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)  // selection 1
        #expect(state.step(backward: false) == .select(index: 2))
        #expect(state.step(backward: true) == .select(index: 1))
        #expect(state.arrow(.right) == .select(index: 2))
    }

    @Test func returnActivates() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.returnKey() == .activate(index: 1))
        #expect(state.phase == .inactive)
    }

    @Test func spaceActivatesInPersistentSessionOnly() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.spaceKey() == .activate(index: 1))
        // in a held session Space is not a WindowHop key
        var heldState = SwitcherState()
        _ = heldState.trigger(backward: false, itemCount: 3)
        #expect(heldState.spaceKey() == .none)
        #expect(heldState.phase == .held)
    }

    @Test func escapeCancels() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.escape() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func clickActivates() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.itemClicked(index: 2) == .activate(index: 2))
    }

    @Test func secondInvocationKeepsCurrentSession() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        _ = state.step(backward: false)  // selection 2
        #expect(state.openPersistent(itemCount: 3) == .none)
        #expect(state.phase == .sticky)
        #expect(state.selectedIndex == 2)
        // also ignored while a held session is running
        var heldState = SwitcherState()
        _ = heldState.trigger(backward: false, itemCount: 3)
        #expect(heldState.openPersistent(itemCount: 3) == .none)
        #expect(heldState.phase == .held)
    }

    @Test func deleteStillRequiresConfirmation() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.deleteKey() == .requestClose(index: 1))
        #expect(state.phase == .confirming)
        _ = state.confirmationFinished()
        #expect(state.phase == .sticky)
    }

    @Test func teardownFromStickyCancels() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        #expect(state.teardown() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func teardownFromStickyCloseConfirmationCancels() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        _ = state.deleteKey()
        #expect(state.escape() == .none)
        #expect(state.teardown() == .cancel)
        #expect(state.phase == .inactive)
    }

    @Test func staleStickyConfirmationIsNotRevivedByANewSession() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        _ = state.deleteKey()
        let stale = state.sessionID
        _ = state.teardown()
        _ = state.openPersistent(itemCount: 3)
        _ = state.deleteKey()
        #expect(!state.isConfirming(sessionID: stale))
        #expect(state.isConfirming(sessionID: state.sessionID))
    }
}
