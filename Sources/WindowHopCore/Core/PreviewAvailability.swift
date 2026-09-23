/// What a window-preview canvas shows while it has no snapshot, or that it has one.
public enum PreviewPresentationState: Equatable, Sendable {
    case loading
    case permissionUnavailable
    case captureUnavailable
    case loaded
}

/// Per-window preview acquisition state for one open session. Pooled tiles are
/// indexed by position and reconfigured on every list refresh, so the state
/// lives here, keyed by the window's stable id: a metadata refresh or a reorder
/// can neither erase a recorded failure nor move it onto another window's card.
///
/// Precedence, first match wins: an image is `loaded`, a permission block is
/// `permissionUnavailable`, a recorded capture failure is `captureUnavailable`,
/// anything else is `loading`.
public struct PreviewAvailability<ID: Hashable> {
    public private(set) var permissionBlocked = false
    private var failed: Set<ID> = []

    public init() {}

    /// A new session starts with no recorded failures and no permission block;
    /// the caller reports the current permission right after.
    public mutating func beginSession() {
        permissionBlocked = false
        failed = []
    }

    public mutating func permissionChanged(authorized: Bool) {
        permissionBlocked = !authorized
    }

    public mutating func captureFailed(_ id: ID) {
        failed.insert(id)
    }

    public mutating func captureSucceeded(_ id: ID) {
        failed.remove(id)
    }

    /// Forgets windows that left the list, so a returning id starts as loading.
    public mutating func retain(_ ids: some Sequence<ID>) {
        failed.formIntersection(ids)
    }

    public func presentation(for id: ID, hasImage: Bool) -> PreviewPresentationState {
        if hasImage { return .loaded }
        if permissionBlocked { return .permissionUnavailable }
        if failed.contains(id) { return .captureUnavailable }
        return .loading
    }
}
