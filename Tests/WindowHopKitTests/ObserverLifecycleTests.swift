import XCTest
@testable import WindowHopKit

final class ObserverLifecycleTests: XCTestCase {
    private func makeLifecycle(attempts: Int = 3) -> ObserverLifecycle {
        ObserverLifecycle(maxAttempts: attempts, retryDelay: 0.5)
    }

    func testStartSubscribesWithAFirstGeneration() {
        var lifecycle = makeLifecycle()
        XCTAssertEqual(lifecycle.handle(.start), [.subscribe(generation: 1)])
        XCTAssertTrue(lifecycle.isCurrent(1))
    }

    func testStopWhileSubscribingIgnoresLaterSuccess() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        XCTAssertEqual(lifecycle.handle(.stop), [.removeObserver])
        XCTAssertEqual(lifecycle.handle(.subscriptionSucceeded(generation: 1)), [])
        XCTAssertEqual(lifecycle.phase, .stopped)
        XCTAssertFalse(lifecycle.isCurrent(1))
    }

    func testRetryAfterStopIsDropped() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        XCTAssertEqual(lifecycle.handle(.subscriptionFailed(generation: 1, retryable: true)),
                       [.scheduleRetry(generation: 1, delay: 0.5)])
        _ = lifecycle.handle(.stop)
        XCTAssertEqual(lifecycle.handle(.retryDue(generation: 1)), [])
        XCTAssertEqual(lifecycle.phase, .stopped)
    }

    func testStartAfterStopDoesNotReviveTheObserver() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        _ = lifecycle.handle(.subscriptionSucceeded(generation: 1))
        _ = lifecycle.handle(.stop)
        XCTAssertEqual(lifecycle.handle(.start), [])
        XCTAssertEqual(lifecycle.handle(.stop), [])
        XCTAssertEqual(lifecycle.phase, .stopped)
    }

    func testRestartUsesANewGenerationAndIgnoresOldResults() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        // the app refused the notification; a later eligibility change restarts
        XCTAssertEqual(lifecycle.handle(.subscriptionFailed(generation: 1, retryable: false)), [])
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertEqual(lifecycle.handle(.start), [.subscribe(generation: 2)])
        XCTAssertEqual(lifecycle.handle(.subscriptionSucceeded(generation: 1)), [])
        XCTAssertEqual(lifecycle.handle(.retryDue(generation: 1)), [])
        XCTAssertFalse(lifecycle.isCurrent(1))
        XCTAssertEqual(lifecycle.handle(.subscriptionSucceeded(generation: 2)),
                       [.subscribeRemainingNotifications(generation: 2), .discoverWindows(generation: 2)])
    }

    func testRetriesStopWhenAttemptsAreExhausted() {
        var lifecycle = makeLifecycle(attempts: 3)
        _ = lifecycle.handle(.start)
        for _ in 1...2 {
            XCTAssertEqual(lifecycle.handle(.subscriptionFailed(generation: 1, retryable: true)),
                           [.scheduleRetry(generation: 1, delay: 0.5)])
            XCTAssertEqual(lifecycle.handle(.retryDue(generation: 1)), [.subscribe(generation: 1)])
        }
        // third attempt fails: no fourth
        XCTAssertEqual(lifecycle.handle(.subscriptionFailed(generation: 1, retryable: true)), [])
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertEqual(lifecycle.handle(.start), [.subscribe(generation: 2)])
    }

    func testDiscoveryIsRequestedOnceForTheFirstSuccess() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        XCTAssertEqual(lifecycle.handle(.subscriptionSucceeded(generation: 1)),
                       [.subscribeRemainingNotifications(generation: 1), .discoverWindows(generation: 1)])
        XCTAssertEqual(lifecycle.handle(.subscriptionSucceeded(generation: 1)), [])
        XCTAssertEqual(lifecycle.phase, .ready(generation: 1))
    }

    func testRepeatedStartWhileReadyDoesNotResubscribe() {
        var lifecycle = makeLifecycle()
        _ = lifecycle.handle(.start)
        XCTAssertEqual(lifecycle.handle(.start), [], "an attempt is already in flight")
        _ = lifecycle.handle(.subscriptionSucceeded(generation: 1))
        XCTAssertEqual(lifecycle.handle(.start), [])
        XCTAssertEqual(lifecycle.phase, .ready(generation: 1))
    }

    func testStopBeforeStartStillRemovesAndStaysStopped() {
        var lifecycle = makeLifecycle()
        XCTAssertEqual(lifecycle.handle(.stop), [.removeObserver])
        XCTAssertEqual(lifecycle.handle(.start), [])
    }
}
