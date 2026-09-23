import Foundation
import Testing

@testable import WindowHopKit

struct ObserverLifecycleTests {
    private func makeLifecycle(attempts: Int = 3) -> ObserverLifecycle {
        ObserverLifecycle(maxAttempts: attempts, retryDelay: 0.5)
    }

    @Test func startSubscribesWithAFirstGeneration() {
        var lifecycle = makeLifecycle()
        #expect(lifecycle.handle(.start) == [.subscribe(generation: 1)])
        #expect(lifecycle.isCurrent(1))
    }

    @Test func stopWhileSubscribingIgnoresLaterSuccess() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        #expect(lifecycle.handle(.stop) == [.removeObserver])
        #expect(lifecycle.handle(.subscriptionSucceeded(generation: 1)) == [])
        #expect(lifecycle.phase == .stopped)
        #expect(!lifecycle.isCurrent(1))
    }

    @Test func retryAfterStopIsDropped() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        #expect(
            lifecycle.handle(.subscriptionFailed(generation: 1, retryable: true)) == [
                .scheduleRetry(generation: 1, delay: 0.5)
            ])
        _ = lifecycle.handle(.stop)
        #expect(lifecycle.handle(.retryDue(generation: 1)) == [])
        #expect(lifecycle.phase == .stopped)
    }

    @Test func startAfterStopDoesNotReviveTheObserver() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        _ = lifecycle.handle(.subscriptionSucceeded(generation: 1))
        _ = lifecycle.handle(.stop)
        #expect(lifecycle.handle(.start) == [])
        #expect(lifecycle.handle(.stop) == [])
        #expect(lifecycle.phase == .stopped)
    }

    @Test func restartUsesANewGenerationAndIgnoresOldResults() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        // the app refused the notification; a later eligibility change restarts
        #expect(lifecycle.handle(.subscriptionFailed(generation: 1, retryable: false)) == [])
        #expect(lifecycle.phase == .idle)
        #expect(lifecycle.handle(.start) == [.subscribe(generation: 2)])
        #expect(lifecycle.handle(.subscriptionSucceeded(generation: 1)) == [])
        #expect(lifecycle.handle(.retryDue(generation: 1)) == [])
        #expect(!lifecycle.isCurrent(1))
        #expect(
            lifecycle.handle(.subscriptionSucceeded(generation: 2)) == [
                .subscribeRemainingNotifications(generation: 2), .discoverWindows(generation: 2),
            ])
    }

    @Test func retriesStopWhenAttemptsAreExhausted() {
        var lifecycle = makeLifecycle(attempts: 3)
        _ = lifecycle.handle(.start)
        for _ in 1...2 {
            #expect(
                lifecycle.handle(.subscriptionFailed(generation: 1, retryable: true)) == [
                    .scheduleRetry(generation: 1, delay: 0.5)
                ])
            #expect(lifecycle.handle(.retryDue(generation: 1)) == [.subscribe(generation: 1)])
        }
        // third attempt fails: no fourth
        #expect(lifecycle.handle(.subscriptionFailed(generation: 1, retryable: true)) == [])
        #expect(lifecycle.phase == .idle)
        #expect(lifecycle.handle(.start) == [.subscribe(generation: 2)])
    }

    @Test func discoveryIsRequestedOnceForTheFirstSuccess() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        #expect(
            lifecycle.handle(.subscriptionSucceeded(generation: 1)) == [
                .subscribeRemainingNotifications(generation: 1), .discoverWindows(generation: 1),
            ])
        #expect(lifecycle.handle(.subscriptionSucceeded(generation: 1)) == [])
        #expect(lifecycle.phase == .ready(generation: 1))
    }

    @Test func repeatedStartWhileReadyDoesNotResubscribe() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        #expect(lifecycle.handle(.start) == [], "an attempt is already in flight")
        _ = lifecycle.handle(.subscriptionSucceeded(generation: 1))
        #expect(lifecycle.handle(.start) == [])
        #expect(lifecycle.phase == .ready(generation: 1))
    }

    @Test func stopBeforeStartStillRemovesAndStaysStopped() {
        var lifecycle = makeLifecycle()
        #expect(lifecycle.handle(.stop) == [.removeObserver])
        #expect(lifecycle.handle(.start) == [])
    }
}
