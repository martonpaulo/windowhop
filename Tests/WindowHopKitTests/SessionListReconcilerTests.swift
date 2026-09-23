import Foundation
import Testing

@testable import WindowHopKit

/// The session list must stay stable under the user's fingers while still
/// surfacing windows that appear mid-session. These are the rules that keep
/// those two requirements from cancelling each other out.
struct SessionListReconcilerTests {
    @Test func survivingEntriesKeepTheirSessionPositions() {
        // the store reports live MRU order; the session must ignore it
        let plan = SessionListReconciler.reconcile(
            sessionIds: ["a", "b", "c"],
            freshIds: ["c", "a", "b"])
        #expect(plan.ids == ["a", "b", "c"])
        #expect(plan.appeared == [])
    }

    @Test func closedWindowIsRemovedInPlace() {
        let plan = SessionListReconciler.reconcile(
            sessionIds: ["a", "b", "c"],
            freshIds: ["a", "c"])
        #expect(plan.ids == ["a", "c"])
        #expect(plan.appeared == [])
    }

    @Test func windowOpenedMidSessionIsAppendedAtTheEnd() {
        // the new window is focused, so the store puts it first; appending keeps
        // every index the user is already cycling through unchanged
        let plan = SessionListReconciler.reconcile(
            sessionIds: ["a", "b"],
            freshIds: ["new", "a", "b"])
        #expect(plan.ids == ["a", "b", "new"])
        #expect(plan.appeared == ["new"])
    }

    @Test func severalNewWindowsAppendInStoreOrder() {
        let plan = SessionListReconciler.reconcile(
            sessionIds: ["a"],
            freshIds: ["x", "y", "a"])
        #expect(plan.ids == ["a", "x", "y"])
        #expect(plan.appeared == ["x", "y"])
    }

    @Test func preservedEntrySurvivesAbsenceAndIsNotReportedAsNew() {
        // location metadata went briefly stale: keep the entry where it was
        let plan = SessionListReconciler.reconcile(
            sessionIds: ["a", "b"],
            freshIds: ["a"],
            preserving: ["b"])
        #expect(plan.ids == ["a", "b"])
        #expect(plan.appeared == [])
    }

    @Test func preservedEntryReturningToTheSnapshotStaysInPlace() {
        let plan = SessionListReconciler.reconcile(
            sessionIds: ["a", "b"],
            freshIds: ["b", "a"],
            preserving: ["b"])
        #expect(plan.ids == ["a", "b"])
        #expect(plan.appeared == [])
    }

    @Test func appendedEntryIsNotAppendedTwiceOnTheNextRefresh() {
        let first = SessionListReconciler.reconcile(sessionIds: ["a"], freshIds: ["new", "a"])
        let second = SessionListReconciler.reconcile(sessionIds: first.ids, freshIds: ["new", "a"])
        #expect(second.ids == ["a", "new"])
        #expect(second.appeared == [])
    }

    @Test func emptySnapshotEmptiesTheListSoTheSessionCanCancel() {
        let plan = SessionListReconciler.reconcile(sessionIds: ["a", "b"], freshIds: [])
        #expect(plan.ids == [])
        #expect(plan.appeared == [])
    }
}
