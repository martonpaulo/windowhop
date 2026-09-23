/// Whether the login session can currently report its windows truthfully (#38).
///
/// A locked screen makes every app publish zero windows over Accessibility (measured by
/// AltTab on macOS 26, upstream `97ec5cb1` and `e32b48e1`), so an enumeration or a
/// liveness probe taken then says "the screen is locked", not "the windows are gone".
/// The same caution covers a session switched away (fast user switching) and a sleeping
/// system: nothing learned in those states may prune a window or move it off the current
/// Space.
///
/// Sleeping displays alone do not block: a Mac used over Screen Sharing can keep its
/// physical displays asleep while the session is in use, and blocking there could freeze
/// the inventory for a whole remote session. Their sleep only marks that a recovery pass
/// is due, which their wake then asks for.
///
/// Recovery is event-driven: after any dark period, the first event that leaves the
/// session usable asks for exactly one re-enumeration, and nothing polls.
public struct SessionAvailability: Equatable, Sendable {
    /// One reason the session cannot report windows right now.
    public enum Condition: Hashable, Sendable, CaseIterable {
        case screenLocked
        case sessionInactive
        case systemAsleep
    }

    /// An operating-system event that starts or ends a dark period.
    public enum Event: String, Sendable, CaseIterable {
        case screenLocked
        case screenUnlocked
        case sessionResignedActive
        case sessionBecameActive
        case displaysSlept
        case displaysWoke
        case systemWillSleep
        case systemDidWake
    }

    public private(set) var conditions: Set<Condition> = []
    /// Changes every time usability changes, so a read that started before a lock and
    /// finished after the unlock can still be recognized as taken across the dark period.
    public private(set) var epoch: UInt64 = 0
    /// A dark period happened since the last recovery pass.
    public private(set) var needsRecovery = false

    public init() {}

    public var isUsable: Bool { conditions.isEmpty }

    /// Applies one event. Returns true when the caller must run one recovery
    /// re-enumeration now: the event ends a dark period and leaves the session usable.
    /// An event that repeats the current state (a second unlock, a wake without a
    /// sleep) asks for nothing.
    @discardableResult
    public mutating func apply(_ event: Event) -> Bool {
        let wasUsable = isUsable
        let endsDarkPeriod: Bool
        switch event {
        case .screenLocked:
            conditions.insert(.screenLocked)
            endsDarkPeriod = false
        case .sessionResignedActive:
            conditions.insert(.sessionInactive)
            endsDarkPeriod = false
        case .systemWillSleep:
            conditions.insert(.systemAsleep)
            endsDarkPeriod = false
        case .displaysSlept: endsDarkPeriod = false
        case .screenUnlocked:
            conditions.remove(.screenLocked)
            endsDarkPeriod = true
        case .sessionBecameActive:
            conditions.remove(.sessionInactive)
            endsDarkPeriod = true
        case .systemDidWake:
            conditions.remove(.systemAsleep)
            endsDarkPeriod = true
        case .displaysWoke: endsDarkPeriod = true
        }
        if wasUsable != isUsable { epoch &+= 1 }
        guard endsDarkPeriod else {
            needsRecovery = true
            return false
        }
        guard isUsable, needsRecovery else { return false }
        needsRecovery = false
        return true
    }

    /// A read started at `epoch` may conclude something only when the session is usable
    /// now and stayed usable for the whole read.
    public func trusts(readStartedAt epoch: UInt64) -> Bool {
        isUsable && epoch == self.epoch
    }
}
