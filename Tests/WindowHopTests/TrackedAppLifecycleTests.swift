import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// Drives real `TrackedApp` observers (against Finder) through overlapping
    /// start/stop requests. Run with `swift test --sanitize=thread` to check that observer
    /// state stays confined to the AX reads queue; without the sanitizer it still checks
    /// that no pending work revives a stopped app.
    @MainActor
    struct TrackedAppLifecycleTests {
        /// Reads each app's phase inside its observer actor, behind the work already queued.
        /// The test suspends while it waits, so the main actor keeps serving the main-queue
        /// hops the observers schedule (XCTest's `wait(for:timeout:)` spun the run loop).
        private func phases(of apps: [TrackedApp]) async -> [ObserverLifecycle.Phase] {
            let observers = apps.map(\.observer)
            return await withCheckedContinuation { read in
                BackgroundWork.axReadsQueue.async {
                    let phases = observers.map { observer in
                        observer.assumeIsolated { $0.lifecycle.phase }
                    }
                    read.resume(returning: phases)
                }
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func stopInvalidatesPendingObserverWorkUnderStress() async throws {
            // the xctest runner is not a registered app (NSRunningApplication.current has
            // pid -1), so observe Finder: subscribing only listens, it changes nothing
            guard
                let process = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.finder"
                ).first
            else {
                try Test.cancel("needs a logged-in session with Finder running")
            }
            // a store that never starts: the discovery each first subscription requests
            // reaches it and is dropped, as it is for an app the store no longer tracks
            let isolated = try IsolatedPreferences()
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
            _ = await phases(of: apps)
            for app in apps { app.stopObserving() }
            for app in apps { app.startObserving() }
            // outlive two retry delays: every pending retry must find its generation stale
            try await Task.sleep(for: .seconds(1.2))
            #expect(await phases(of: apps) == Array(repeating: .stopped, count: apps.count))
        }
    }
}
