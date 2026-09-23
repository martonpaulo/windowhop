import Foundation
import Testing

@testable import WindowHopKit

struct LoginItemStatusTests {
    /// The toggle is on whenever WindowHop is registered: a pending approval
    /// is still a registration, and turning the toggle off removes it.
    @Test func toggleIsOnForEveryRegisteredState() {
        let on = LoginItemStatus.allCases.filter(\.isOn)
        #expect(Set(on) == [.enabled, .requiresApproval])
    }

    @Test func onlyAnUnavailableItemLocksTheToggle() {
        let locked = LoginItemStatus.allCases.filter { !$0.allowsChange }
        #expect(locked == [.unavailable])
        #expect(
            !LoginItemStatus.unavailable.isOn,
            "a locked toggle must never hide a registration it cannot remove")
    }

    @Test func onlyPendingApprovalOffersLoginItemsSettings() {
        let offering = LoginItemStatus.allCases.filter(\.offersLoginItemsSettings)
        #expect(offering == [.requiresApproval])
    }

    /// States the toggle alone cannot express carry a sentence, so they are
    /// not signalled by the switch position (or color) alone.
    @Test func statesTheToggleCannotExpressAreExplained() {
        #expect(LoginItemStatus.enabled.explanation == nil)
        #expect(LoginItemStatus.disabled.explanation == nil)
        #expect(LoginItemStatus.requiresApproval.explanation?.contains("Login Items") == true)
        #expect(LoginItemStatus.unavailable.explanation?.contains("Applications folder") == true)
    }
}
