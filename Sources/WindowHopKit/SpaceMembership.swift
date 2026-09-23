/// The outcome of reading one app's window list (`kAXWindows`). A failed read must
/// never masquerade as an empty inventory: an app that timed out still owns every
/// window it had a moment ago, while an app that legitimately lists zero windows on
/// this Space really has none here.
public enum WindowEnumeration<ID: Hashable>: Equatable {
    /// The read succeeded. An empty set is a valid answer: no window on this Space.
    case listed(Set<ID>)
    /// The read failed transiently (timeout, `.cannotComplete`, any other AX error):
    /// nothing is known about the current inventory.
    case unavailable
    /// The app element itself is dead (`.invalidUIElement`): its windows may be too.
    case applicationInvalid

    /// The listed windows, or nil when the read did not produce a trustworthy list.
    public var listedWindows: Set<ID>? {
        if case .listed(let windows) = self { return windows }
        return nil
    }
}

/// Decides how a Space-change re-enumeration updates the tracked windows of one app.
public enum SpaceMembership {
    public struct Reconciliation<ID: Hashable> {
        /// The new current-Space flag of each tracked window; absent means keep the
        /// last known flag.
        public var currentSpace: [ID: Bool]
        /// Tracked windows that may be dead and need a liveness check before removal.
        public var suspects: [ID]
    }

    /// Only a successful read may change current-Space flags. A window absent from a
    /// successful list is either on another Space or silently dead, so it becomes a
    /// suspect. An invalid app element changes no flags but makes every window a
    /// suspect, so the liveness check removes the ones that are really gone.
    public static func reconcile<ID: Hashable>(tracked: [ID],
                                               enumeration: WindowEnumeration<ID>) -> Reconciliation<ID> {
        switch enumeration {
        case .listed(let current):
            var flags = [ID: Bool]()
            var suspects = [ID]()
            for id in tracked {
                let isCurrent = current.contains(id)
                flags[id] = isCurrent
                if !isCurrent { suspects.append(id) }
            }
            return Reconciliation(currentSpace: flags, suspects: suspects)
        case .unavailable:
            return Reconciliation(currentSpace: [:], suspects: [])
        case .applicationInvalid:
            return Reconciliation(currentSpace: [:], suspects: tracked)
        }
    }
}
