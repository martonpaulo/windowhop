import XCTest
@testable import WindowHopCore

final class LoginItemStatusTests: XCTestCase {
    /// The toggle is on whenever WindowHop is registered: a pending approval
    /// is still a registration, and turning the toggle off removes it.
    func testToggleIsOnForEveryRegisteredState() {
        let on = LoginItemStatus.allCases.filter(\.isOn)
        XCTAssertEqual(Set(on), [.enabled, .requiresApproval])
    }

    func testOnlyAnUnavailableItemLocksTheToggle() {
        let locked = LoginItemStatus.allCases.filter { !$0.allowsChange }
        XCTAssertEqual(locked, [.unavailable])
        XCTAssertFalse(LoginItemStatus.unavailable.isOn,
                       "a locked toggle must never hide a registration it cannot remove")
    }

    func testOnlyPendingApprovalOffersLoginItemsSettings() {
        let offering = LoginItemStatus.allCases.filter(\.offersLoginItemsSettings)
        XCTAssertEqual(offering, [.requiresApproval])
    }

    /// States the toggle alone cannot express carry a sentence, so they are
    /// not signalled by the switch position (or color) alone.
    func testStatesTheToggleCannotExpressAreExplained() {
        XCTAssertNil(LoginItemStatus.enabled.explanation)
        XCTAssertNil(LoginItemStatus.disabled.explanation)
        XCTAssertTrue(LoginItemStatus.requiresApproval.explanation?.contains("Login Items") == true)
        XCTAssertTrue(LoginItemStatus.unavailable.explanation?.contains("Applications folder") == true)
    }
}
