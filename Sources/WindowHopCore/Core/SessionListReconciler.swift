/// Reconciles the list shown by an open switcher session against a fresh store
/// snapshot. Two competing needs meet here:
///
/// - Cycling must stay predictable. A tile may not move out from under the
///   user's fingers mid-session, so every surviving entry keeps its position
///   and the list is never reordered into the store's live MRU order.
/// - The user must never be blind to a window that appeared. A window opened
///   while the panel is up (a launching app, a new document, a dialog) has to
///   become reachable in the same session rather than only after reopening.
///
/// Appending newcomers at the end satisfies both: existing indices are stable,
/// and the new window is one step away. The session list therefore only ever
/// loses entries in place or grows at the end.
public enum SessionListReconciler {
    public struct Plan<ID: Hashable>: Equatable {
        /// The reconciled session order: surviving entries in their frozen
        /// positions, then the windows that appeared, in store order.
        public var ids: [ID]
        /// The suffix of `ids` that was not part of the session before this
        /// refresh. Callers use it to start work scoped to new entries only.
        public var appeared: [ID]

        public init(ids: [ID], appeared: [ID]) {
            self.ids = ids
            self.appeared = appeared
        }
    }

    /// - Parameters:
    ///   - sessionIds: the currently displayed entries, in session order.
    ///   - freshIds: everything currently eligible, in store order.
    ///   - preserved: session entries absent from `freshIds` that must survive
    ///     anyway. Location metadata (Space, display) goes briefly stale while
    ///     macOS updates it, and dropping an entry for that would make the list
    ///     flicker; the caller decides which absences are transient.
    public static func reconcile<ID: Hashable>(
        sessionIds: [ID],
        freshIds: [ID],
        preserving preserved: Set<ID> = []
    ) -> Plan<ID> {
        let fresh = Set(freshIds)
        let kept = sessionIds.filter { fresh.contains($0) || preserved.contains($0) }
        let known = Set(kept)
        let appeared = freshIds.filter { !known.contains($0) }
        return Plan(ids: kept + appeared, appeared: appeared)
    }
}
