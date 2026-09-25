import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// A departure reported by `NSWorkspace.runningApplications` removes the tracked app
    /// even while its `isTerminated` still reads false (#136). Driven against the live
    /// Finder object: only the test store's own tracking changes, Finder is never signalled.
    @MainActor
    final class AppRemovalTests {
        private var isolated: IsolatedPreferences!
        private var store: WindowStore!

        init() throws {
            isolated = try IsolatedPreferences()
            store = WindowStore(preferences: isolated.preferences, previews: isolated.previews)
        }

        isolated deinit {
            store.stop()
            store = nil
            isolated.remove()
            isolated = nil
        }

        private func trackedFinder() throws -> NSRunningApplication {
            guard
                let finder = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.finder"
                ).first
            else {
                try Test.cancel("needs a logged-in session with Finder running")
            }
            store.start()
            #expect(store.apps[finder.processIdentifier] != nil, "the started store tracks Finder")
            return finder
        }

        @Test func aDepartedAppIsRemovedBeforeItReportsTerminated() throws {
            let finder = try trackedFinder()
            #expect(!finder.isTerminated)

            store.runningApplicationsChanged(launched: [], departed: [finder], stillListed: [])

            #expect(store.apps[finder.processIdentifier] == nil)
            #expect(!store.windows.contains { $0.app?.pid == finder.processIdentifier })
        }

        @Test func aStillListedAppIsKept() throws {
            let finder = try trackedFinder()

            store.runningApplicationsChanged(launched: [], departed: [finder], stillListed: [finder])

            #expect(store.apps[finder.processIdentifier] != nil)
        }
    }
}
