import XCTest
@testable import WindowHopCore

final class PersistentSessionTests: XCTestCase {
    func testOpenSelectsPreviousWindow() {
        var state = SwitcherState()
        XCTAssertEqual(state.openPersistent(itemCount: 4), .show(selectedIndex: 1))
        XCTAssertEqual(state.phase, .sticky)
    }

    func testOpenWithZeroWindowsDoesNothing() {
        var state = SwitcherState()
        XCTAssertEqual(state.openPersistent(itemCount: 0), .none)
        XCTAssertEqual(state.phase, .inactive)
    }

    func testOpenWithOneWindowSelectsIt() {
        var state = SwitcherState()
        XCTAssertEqual(state.openPersistent(itemCount: 1), .show(selectedIndex: 0))
    }

    func testModifierReleaseDoesNotCloseOrActivate() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertEqual(state.modifierReleased(), .none)
        XCTAssertEqual(state.phase, .sticky)
    }

    func testNavigationWorksWithoutHeldModifier() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3) // selection 1
        XCTAssertEqual(state.step(backward: false), .select(index: 2))
        XCTAssertEqual(state.step(backward: true), .select(index: 1))
        XCTAssertEqual(state.arrow(.right), .select(index: 2))
    }

    func testReturnActivates() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertEqual(state.returnKey(), .activate(index: 1))
        XCTAssertEqual(state.phase, .inactive)
    }

    func testSpaceActivatesInPersistentSessionOnly() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertEqual(state.spaceKey(), .activate(index: 1))
        // in a held session Space is not a WindowHop key
        var heldState = SwitcherState()
        _ = heldState.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(heldState.spaceKey(), .none)
        XCTAssertEqual(heldState.phase, .held)
    }

    func testEscapeCancels() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertEqual(state.escape(), .cancel)
        XCTAssertEqual(state.phase, .inactive)
    }

    func testClickActivates() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertEqual(state.itemClicked(index: 2), .activate(index: 2))
    }

    func testSecondInvocationKeepsCurrentSession() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        _ = state.step(backward: false) // selection 2
        XCTAssertEqual(state.openPersistent(itemCount: 3), .none)
        XCTAssertEqual(state.phase, .sticky)
        XCTAssertEqual(state.selectedIndex, 2)
        // also ignored while a held session is running
        var heldState = SwitcherState()
        _ = heldState.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(heldState.openPersistent(itemCount: 3), .none)
        XCTAssertEqual(heldState.phase, .held)
    }

    func testDeleteStillRequiresConfirmation() {
        var state = SwitcherState()
        _ = state.openPersistent(itemCount: 3)
        XCTAssertEqual(state.deleteKey(), .requestClose(index: 1))
        XCTAssertEqual(state.phase, .confirming)
        _ = state.confirmationFinished()
        XCTAssertEqual(state.phase, .sticky)
    }
}
