import XCTest
@testable import WindowHopCore

final class SwitcherStateTests: XCTestCase {
    // MARK: - Opening

    func testTriggerWithZeroWindowsDoesNothing() {
        var state = SwitcherState()
        XCTAssertEqual(state.trigger(backward: false, itemCount: 0), .none)
        XCTAssertEqual(state.phase, .inactive)
    }

    func testTriggerWithOneWindowSelectsIt() {
        var state = SwitcherState()
        XCTAssertEqual(state.trigger(backward: false, itemCount: 1), .show(selectedIndex: 0))
        XCTAssertEqual(state.phase, .held)
    }

    func testTriggerSelectsPreviousWindow() {
        var state = SwitcherState()
        XCTAssertEqual(state.trigger(backward: false, itemCount: 5), .show(selectedIndex: 1))
    }

    func testBackwardTriggerSelectsLastWindow() {
        var state = SwitcherState()
        XCTAssertEqual(state.trigger(backward: true, itemCount: 5), .show(selectedIndex: 4))
    }

    // MARK: - Cycling and wrapping

    func testForwardCyclingWraps() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3) // selection 1
        XCTAssertEqual(state.step(backward: false), .select(index: 2))
        XCTAssertEqual(state.step(backward: false), .select(index: 0))
        XCTAssertEqual(state.step(backward: false), .select(index: 1))
    }

    func testBackwardCyclingWraps() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3) // selection 1
        XCTAssertEqual(state.step(backward: true), .select(index: 0))
        XCTAssertEqual(state.step(backward: true), .select(index: 2))
    }

    func testShiftMayBePressedAndReleasedMidSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4) // 1
        _ = state.step(backward: false) // 2
        _ = state.step(backward: true) // 1
        XCTAssertEqual(state.step(backward: false), .select(index: 2))
    }

    func testArrowDirections() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4) // 1
        XCTAssertEqual(state.arrow(.down), .select(index: 2))
        XCTAssertEqual(state.arrow(.up), .select(index: 1))
        XCTAssertEqual(state.arrow(.right), .select(index: 2))
        XCTAssertEqual(state.arrow(.left), .select(index: 1))
    }

    // MARK: - Ending the session

    func testModifierReleaseActivatesSelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.step(backward: false)
        XCTAssertEqual(state.modifierReleased(), .activate(index: 2))
        XCTAssertEqual(state.phase, .inactive)
    }

    func testEscapeCancelsWithoutActivating() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.escape(), .cancel)
        XCTAssertEqual(state.phase, .inactive)
    }

    func testReturnActivatesSelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.returnKey(), .activate(index: 1))
    }

    func testClickActivatesClickedItem() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.itemClicked(index: 2), .activate(index: 2))
        XCTAssertEqual(state.phase, .inactive)
    }

    func testClickOutsideValidRangeIsIgnored() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.itemClicked(index: 7), .none)
        XCTAssertEqual(state.phase, .held)
    }

    func testOutsideClickCancels() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.outsideClick(), .cancel)
    }

    func testEventsWhileInactiveAreIgnored() {
        var state = SwitcherState()
        XCTAssertEqual(state.modifierReleased(), .none)
        XCTAssertEqual(state.escape(), .none)
        XCTAssertEqual(state.returnKey(), .none)
        XCTAssertEqual(state.step(backward: false), .none)
        XCTAssertEqual(state.deleteKey(), .none)
    }

    // MARK: - Close confirmation

    func testDeleteRequestsCloseAndSuspendsSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.deleteKey(), .requestClose(index: 1))
        XCTAssertEqual(state.phase, .confirming)
    }

    func testModifierReleaseDuringConfirmationDoesNotActivate() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        XCTAssertEqual(state.modifierReleased(), .none)
        XCTAssertEqual(state.phase, .confirming)
    }

    func testTriggerDuringConfirmationIsIgnored() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        XCTAssertEqual(state.trigger(backward: false, itemCount: 3), .none)
    }

    func testSessionContinuesStickyAfterConfirmation() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        _ = state.deleteKey()
        XCTAssertEqual(state.confirmationFinished(), .none)
        XCTAssertEqual(state.phase, .sticky)
        // navigation still works without a held modifier
        XCTAssertEqual(state.step(backward: false), .select(index: 2))
        XCTAssertEqual(state.modifierReleased(), .none)
        XCTAssertEqual(state.returnKey(), .activate(index: 2))
    }

    // MARK: - List changes while open

    func testWindowClosingKeepsNearbySelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4)
        _ = state.step(backward: false) // selection 2
        XCTAssertEqual(state.listChanged(itemCount: 3, preferredIndex: 2), .select(index: 2))
        XCTAssertEqual(state.listChanged(itemCount: 2, preferredIndex: 2), .select(index: 1))
    }

    func testListBecomingEmptyCancels() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 2)
        XCTAssertEqual(state.listChanged(itemCount: 0, preferredIndex: nil), .cancel)
        XCTAssertEqual(state.phase, .inactive)
    }

    func testResetEndsSession() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        state.reset()
        XCTAssertEqual(state.phase, .inactive)
        XCTAssertEqual(state.modifierReleased(), .none)
    }
}

extension SwitcherStateTests {
    // MARK: - Hover close routing and appearance preference

    func testHoverCloseRequestTargetsExplicitIndexWithoutMovingSelection() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 4) // selection 1
        XCTAssertEqual(state.closeRequested(index: 3), .requestClose(index: 3))
        XCTAssertEqual(state.phase, .confirming)
        // cancelling restores the exact previous selection
        _ = state.confirmationFinished()
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testHoverCloseRequestOutOfRangeIsIgnored() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 2)
        XCTAssertEqual(state.closeRequested(index: 5), .none)
        XCTAssertEqual(state.phase, .held)
    }

    func testDeleteRoutesThroughTheSameCloseRequestFlow() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3)
        XCTAssertEqual(state.deleteKey(), .requestClose(index: 1))
        XCTAssertEqual(state.phase, .confirming)
    }

    func testAppearanceModeDefaultsToAppIcons() {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.appearanceMode, .appIcons)
        preferences.appearanceMode = .windowPreviews
        XCTAssertEqual(preferences.appearanceMode, .windowPreviews)
        defaults.set("garbage", forKey: Preferences.Key.appearanceMode.rawValue)
        XCTAssertEqual(preferences.appearanceMode, .appIcons)
    }
}
