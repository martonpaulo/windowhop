import AppKit
import Synchronization
import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// Drives real `TrackedApp` observers (against Finder) through overlapping
/// start/stop requests. Run with `swift test --sanitize=thread` to check that observer
/// state stays confined to the AX reads queue; without the sanitizer it still checks
/// that no pending work revives a stopped app.
@MainActor
final class TrackedAppLifecycleTests: XCTestCase {
    /// Reads each app's phase inside its observer actor, behind the work already queued.
    /// Waiting on an expectation keeps the main run loop serving the main-queue hops
    /// the observers schedule.
    private func phases(of apps: [TrackedApp]) -> [ObserverLifecycle.Phase] {
        let read = expectation(description: "phases read on the AX reads queue")
        let observers = apps.map(\.observer)
        let result = Mutex<[ObserverLifecycle.Phase]>([])
        BackgroundWork.axReadsQueue.async {
            let phases = observers.map { observer in
                observer.assumeIsolated { $0.lifecycle.phase }
            }
            result.withLock { $0 = phases }
            read.fulfill()
        }
        wait(for: [read], timeout: 30)
        return result.withLock { $0 }
    }

    private func spinMainRunLoop(for seconds: TimeInterval) {
        let elapsed = expectation(description: "delay elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: seconds + 30)
    }

    func testStopInvalidatesPendingObserverWorkUnderStress() throws {
        // the xctest runner is not a registered app (NSRunningApplication.current has
        // pid -1), so observe Finder: subscribing only listens, it changes nothing
        guard let process = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder").first else {
            throw XCTSkip("needs a logged-in session with Finder running")
        }
        // a store that never starts: the discovery each first subscription requests
        // reaches it and is dropped, as it is for an app the store no longer tracks
        let isolated = IsolatedPreferences()
        defer { isolated.remove() }
        let store = WindowStore(preferences: isolated.preferences, previews: isolated.previews)
        let apps = (0..<40).map { _ in TrackedApp(process, router: store.router) }
        for (index, app) in apps.enumerated() {
            app.startObserving()
            app.startObserving()
            if index.isMultiple(of: 2) {
                app.stopObserving()
                app.startObserving()
            }
        }
        // let first attempts land, and possibly schedule retries, before stopping the rest
        _ = phases(of: apps)
        apps.forEach { $0.stopObserving() }
        apps.forEach { $0.startObserving() }
        // outlive two retry delays: every pending retry must find its generation stale
        spinMainRunLoop(for: 1.2)
        XCTAssertEqual(phases(of: apps), Array(repeating: .stopped, count: apps.count))
    }
}
