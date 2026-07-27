import XCTest
@testable import WindowHopCore

/// The session list must stay stable under the user's fingers while still
/// surfacing windows that appear mid-session. These are the rules that keep
/// those two requirements from cancelling each other out.
final class SessionListReconcilerTests: XCTestCase {
    func testSurvivingEntriesKeepTheirSessionPositions() {
        // the store reports live MRU order; the session must ignore it
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b", "c"],
                                                   freshIds: ["c", "a", "b"])
        XCTAssertEqual(plan.ids, ["a", "b", "c"])
        XCTAssertEqual(plan.appeared, [])
    }

    func testClosedWindowIsRemovedInPlace() {
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b", "c"],
                                                   freshIds: ["a", "c"])
        XCTAssertEqual(plan.ids, ["a", "c"])
        XCTAssertEqual(plan.appeared, [])
    }

    func testWindowOpenedMidSessionIsAppendedAtTheEnd() {
        // the new window is focused, so the store puts it first; appending keeps
        // every index the user is already cycling through unchanged
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b"],
                                                   freshIds: ["new", "a", "b"])
        XCTAssertEqual(plan.ids, ["a", "b", "new"])
        XCTAssertEqual(plan.appeared, ["new"])
    }

    func testSeveralNewWindowsAppendInStoreOrder() {
        let plan = SessionListReconciler.reconcile(sessionIds: ["a"],
                                                   freshIds: ["x", "y", "a"])
        XCTAssertEqual(plan.ids, ["a", "x", "y"])
        XCTAssertEqual(plan.appeared, ["x", "y"])
    }

    func testPreservedEntrySurvivesAbsenceAndIsNotReportedAsNew() {
        // location metadata went briefly stale: keep the entry where it was
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b"],
                                                   freshIds: ["a"],
                                                   preserving: ["b"])
        XCTAssertEqual(plan.ids, ["a", "b"])
        XCTAssertEqual(plan.appeared, [])
    }

    func testPreservedEntryReturningToTheSnapshotStaysInPlace() {
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b"],
                                                   freshIds: ["b", "a"],
                                                   preserving: ["b"])
        XCTAssertEqual(plan.ids, ["a", "b"])
        XCTAssertEqual(plan.appeared, [])
    }

    func testAppendedEntryIsNotAppendedTwiceOnTheNextRefresh() {
        let first = SessionListReconciler.reconcile(sessionIds: ["a"], freshIds: ["new", "a"])
        let second = SessionListReconciler.reconcile(sessionIds: first.ids, freshIds: ["new", "a"])
        XCTAssertEqual(second.ids, ["a", "new"])
        XCTAssertEqual(second.appeared, [])
    }

    func testEmptySnapshotEmptiesTheListSoTheSessionCanCancel() {
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b"], freshIds: [])
        XCTAssertEqual(plan.ids, [])
        XCTAssertEqual(plan.appeared, [])
    }
}
