/// Pure bookkeeping for asynchronous preview captures: which windows may still
/// receive results, and which session generation is current. Captures finish
/// out of order and can outlive their window or their session — the ledger is
/// the single rule set deciding what a late result may do:
///
/// - A result for a window that disappeared (evicted) is discarded entirely;
///   it can neither enter the cache nor reach the panel.
/// - A result from a previous session may still enter the cache (free
///   freshness for the next open) but is never delivered live, so a reopened
///   switcher can't receive images ordered for an earlier list.
public struct PreviewLedger<ID: Hashable> {
    public private(set) var generation = 0
    private var validIds: Set<ID> = []

    public init() {}

    /// A session opened: bump the generation (in-flight deliveries from older
    /// sessions become stale) and register the windows that may receive results.
    public mutating func beginSession(ids: some Sequence<ID>) -> Int {
        generation += 1
        validIds.formUnion(ids)
        return generation
    }

    /// The session ended: any not-yet-delivered result loses live delivery.
    public mutating func endSession() {
        generation += 1
    }

    /// The window disappeared: in-flight results for it must be discarded.
    public mutating func evict(_ id: ID) {
        validIds.remove(id)
    }

    public mutating func evictAll() {
        validIds.removeAll()
    }

    /// A finished capture may be cached only while its window is still valid.
    public func shouldStore(_ id: ID) -> Bool {
        validIds.contains(id)
    }

    /// Live delivery additionally requires the originating session to still be
    /// the current one.
    public func shouldDeliver(_ id: ID, capturedIn captureGeneration: Int) -> Bool {
        shouldStore(id) && captureGeneration == generation
    }
}
