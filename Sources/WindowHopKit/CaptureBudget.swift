import Foundation

/// One ceiling on concurrent preview captures, shared by every capture path:
/// the session's initial list, windows that join an open session, and the
/// dwell snapshot.
///
/// Each of those paths used to limit only its own call, so overlapping calls
/// stacked up: with ten windows opening 50 ms apart during a session, up to 10
/// captures were in flight at once (measured in #86). The window server
/// completes captures roughly one after another, so the extra overlap only
/// made each capture wait longer.
///
/// A slot is handed to the next waiter the moment a capture finishes, so a
/// slow capture never holds back a whole wave. Waiting work belongs to a
/// generation: when the generation moves on (the session ended or was
/// replaced), waiters are refused and never start, while work that already
/// holds a slot finishes and releases it normally.
///
/// Main-actor isolated like the capture pipeline that uses it, which runs on
/// the main actor between its awaits.
@MainActor
public final class CaptureBudget {
    public let limit: Int

    private struct Waiter {
        let generation: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var inUse = 0
    private var generation = 0
    private var waiters: [Waiter] = []

    public init(limit: Int) {
        precondition(limit > 0, "a capture budget needs at least one slot")
        self.limit = limit
    }

    /// Captures currently holding a slot.
    public var inFlight: Int { inUse }

    /// Waits for a free slot. Returns true with a slot held, which the caller
    /// must give back with `release()`, or false without one when `requested`
    /// is not, or stops being, the current generation. Work the user is
    /// waiting on right now (the dwell snapshot) passes `jumpingQueue` to be
    /// served before queued tile captures.
    public func acquire(generation requested: Int, jumpingQueue: Bool = false) async -> Bool {
        guard requested == generation else { return false }
        if inUse < limit {
            inUse += 1
            return true
        }
        return await withCheckedContinuation { continuation in
            let waiter = Waiter(generation: requested, continuation: continuation)
            if jumpingQueue {
                waiters.insert(waiter, at: 0)
            } else {
                waiters.append(waiter)
            }
        }
    }

    /// Gives a slot back; the first waiter in line, if any, receives it directly.
    public func release() {
        guard !waiters.isEmpty else {
            inUse -= 1
            return
        }
        waiters.removeFirst().continuation.resume(returning: true)
    }

    /// Makes `newGeneration` current and refuses every waiter of another one.
    public func advance(to newGeneration: Int) {
        generation = newGeneration
        let refused = waiters.filter { $0.generation != newGeneration }
        waiters.removeAll { $0.generation != newGeneration }
        for waiter in refused { waiter.continuation.resume(returning: false) }
    }
}
