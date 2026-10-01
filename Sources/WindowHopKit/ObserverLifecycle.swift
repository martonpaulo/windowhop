import Foundation

/// Pure lifecycle of one app's AX observer subscription: events in, commands out.
/// The Engine owns one per `TrackedApp` and feeds it only from the AX reads queue,
/// so the state has a single serialized owner.
///
/// Every subscription attempt belongs to a generation. Work scheduled for an older
/// generation (a pending retry, a late subscription result) finds its generation no
/// longer current and yields no command, so it can neither resubscribe nor trigger
/// window discovery. `stop` is terminal: nothing after it revives the observer.
///
/// Phases:
/// - idle:        not subscribed; `start` begins a new generation (first launch, or a
///                restart after retries ran out or the app refused the subscription),
///                and `revive` begins one with a single attempt
/// - subscribing: an attempt of the current generation is in flight or scheduled
/// - ready:       the app accepted the first notification; later `start`s are no-ops
/// - stopped:     the app is no longer tracked
public struct ObserverLifecycle: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case subscribing(generation: UInt64, attemptsLeft: Int)
        case ready(generation: UInt64)
        case stopped
    }

    public enum Event: Equatable, Sendable {
        /// The app is eligible for observation (launched, activation policy allows it).
        case start
        /// The user is about to need the app's windows (a switcher session started, or
        /// the app was activated): an observer that gave up or was refused tries once
        /// more. One attempt and no retries, so a hung app costs one attempt per trigger
        /// (#156).
        case revive
        /// The first app-level notification was accepted.
        case subscriptionSucceeded(generation: UInt64)
        /// The attempt failed; `retryable` when the app was merely unresponsive
        /// (mid-launch) rather than refusing the notification for good.
        case subscriptionFailed(generation: UInt64, retryable: Bool)
        /// A scheduled retry's delay elapsed.
        case retryDue(generation: UInt64)
        /// The app is going away.
        case stop
    }

    public enum Command: Equatable, Sendable {
        /// Create the observer if needed and attempt the first app-level subscription.
        case subscribe(generation: UInt64)
        /// Deliver `.retryDue(generation)` after `delay` seconds.
        case scheduleRetry(generation: UInt64, delay: TimeInterval)
        /// Subscribe the app's remaining notifications.
        case subscribeRemainingNotifications(generation: UInt64)
        /// Enumerate the app's existing windows.
        case discoverWindows(generation: UInt64)
        /// Detach the observer from its run loop and release it.
        case removeObserver
    }

    public let maxAttempts: Int
    public let retryDelay: TimeInterval
    public private(set) var phase: Phase = .idle
    /// The most recently started generation; 0 before the first `start`.
    public private(set) var generation: UInt64 = 0

    public init(maxAttempts: Int, retryDelay: TimeInterval) {
        precondition(maxAttempts > 0, "at least one attempt is required")
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
    }

    /// Whether work tagged with `generation` may still touch the observer: its
    /// subscription is in flight or established, and the app was not stopped.
    public func isCurrent(_ generation: UInt64) -> Bool {
        switch phase {
        case .subscribing(let current, _), .ready(let current):
            return current == generation
        case .idle, .stopped:
            return false
        }
    }

    public mutating func handle(_ event: Event) -> [Command] {
        switch (phase, event) {
        case (.stopped, _):
            return []
        case (_, .stop):
            phase = .stopped
            return [.removeObserver]
        case (.idle, .start):
            generation &+= 1
            phase = .subscribing(generation: generation, attemptsLeft: maxAttempts)
            return [.subscribe(generation: generation)]
        case (.idle, .revive):
            generation &+= 1
            phase = .subscribing(generation: generation, attemptsLeft: 1)
            return [.subscribe(generation: generation)]
        case (.subscribing, .start), (.ready, .start), (.subscribing, .revive), (.ready, .revive):
            // an attempt is already running, or the app is already observed
            return []
        case (.subscribing(let current, _), .subscriptionSucceeded(let result)) where result == current:
            phase = .ready(generation: current)
            return [
                .subscribeRemainingNotifications(generation: current),
                .discoverWindows(generation: current),
            ]
        case (.subscribing(let current, let attemptsLeft), .subscriptionFailed(let result, let retryable))
        where result == current:
            guard retryable, attemptsLeft > 1 else {
                // retries exhausted or refused: a later `start` restarts with a new generation
                phase = .idle
                return []
            }
            phase = .subscribing(generation: current, attemptsLeft: attemptsLeft - 1)
            return [.scheduleRetry(generation: current, delay: retryDelay)]
        case (.subscribing(let current, _), .retryDue(let result)) where result == current:
            return [.subscribe(generation: current)]
        case (_, .subscriptionSucceeded), (_, .subscriptionFailed), (_, .retryDue):
            // a result or retry of an older generation, or one that arrives out of phase
            return []
        }
    }
}
