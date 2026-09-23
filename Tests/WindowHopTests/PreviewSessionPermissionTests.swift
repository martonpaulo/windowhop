import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// The Screen Recording preflight costs 14–18 ms on the main thread (#120).
    /// A session reads it once when it opens; windows that join reuse that read,
    /// and only a capture failure reads it again, so a revoked grant still reaches
    /// the permission-blocked presentation (#51).
    @MainActor
    final class PreviewSessionPermissionTests {
        private var isolated: IsolatedPreferences!
        private var savedPermissionRequired: ((ScreenRecordingPermission.Status) -> Void)?
        private var savedUnavailable: ((AnyHashable) -> Void)?
        private var reads = 0
        private var readStatus: ScreenRecordingPermission.Status = .authorized
        private var permissionReports: [ScreenRecordingPermission.Status] = []

        private var provider: PreviewProvider { isolated.previews }

        init() throws {
            isolated = try IsolatedPreferences()
            isolated.preferences.appearanceMode = .windowPreviews
            savedPermissionRequired = provider.onPermissionRequired
            savedUnavailable = provider.onPreviewUnavailable
            provider.readPermissionStatus = { [unowned self] in
                reads += 1
                return readStatus
            }
            provider.onPermissionRequired = { [unowned self] status in
                permissionReports.append(status)
            }
            provider.onPreviewUnavailable = nil
        }

        isolated deinit {
            provider.endSession()
            provider.readPermissionStatus = { ScreenRecordingPermission.status }
            provider.onPermissionRequired = savedPermissionRequired
            provider.onPreviewUnavailable = savedUnavailable
            isolated.remove()
            isolated = nil
        }

        /// Items without a live window make no capture request, so no real
        /// screenshot or shareable-content lookup is ever started.
        private func items(_ ids: [String]) -> [SwitcherItem] {
            ids.map {
                SwitcherItem(
                    id: $0, window: nil, title: "Window \($0)",
                    appName: "TestApp", icon: nil, tabCount: nil)
            }
        }

        private func begin(_ status: ScreenRecordingPermission.Status) {
            provider.beginSession(
                items: items(["a"]), targetSize: CGSize(width: 100, height: 60),
                scale: 2, permissionStatus: status)
        }

        private func join(_ ids: [String]) {
            provider.extendSession(
                items: items(ids), targetSize: CGSize(width: 100, height: 60),
                scale: 2)
        }

        @Test func joiningWindowsReuseTheSessionStatus() {
            begin(.authorized)
            for batch in 0..<10 { join(["join-\(batch)"]) }

            #expect(reads == 0, "a joining window must not read the permission again")
            #expect(provider.sessionPermissionForTesting == .authorized)
        }

        @Test func aBlockedSessionReportsTheStatusItWasOpenedWith() {
            begin(.denied)

            #expect(permissionReports == [.denied])
            #expect(reads == 0)
            #expect(provider.sessionPermissionForTesting == nil, "a blocked session captures nothing")
        }

        /// The #51 presentation still follows a real change: a failure batch reads
        /// the status once and a revoked grant blocks the panel.
        @Test func aFailureAfterARevokedGrantBlocksThePanelOnce() throws {
            begin(.authorized)
            let generation = try #require(provider.sessionGenerationForTesting)
            readStatus = .denied

            provider.markUnavailable(["a", "b", "c"], generation: generation)

            #expect(reads == 1, "one read per failure batch, not one per window")
            #expect(permissionReports == [.denied])
            #expect(provider.sessionPermissionForTesting == .denied)

            provider.markUnavailable(["d"], generation: generation)
            join(["late"])
            #expect(reads == 1, "a session already blocked does not read again")
            #expect(permissionReports == [.denied])
        }

        @Test func aFailureWithTheGrantIntactKeepsTheSessionAuthorized() throws {
            begin(.authorized)
            let generation = try #require(provider.sessionGenerationForTesting)

            provider.markUnavailable(["a", "b"], generation: generation)

            #expect(reads == 1)
            #expect(permissionReports.isEmpty)
            #expect(provider.sessionPermissionForTesting == .authorized)
        }

        @Test func aFailureFromAnEndedSessionReadsNothing() throws {
            begin(.authorized)
            let generation = try #require(provider.sessionGenerationForTesting)
            provider.endSession()
            readStatus = .denied

            provider.markUnavailable(["a"], generation: generation)

            #expect(reads == 0)
            #expect(permissionReports.isEmpty)
        }

        // MARK: - Retry allowance (#91)

        /// A retry is failure-driven work, so it confirms the grant once for the
        /// batch: a revoked grant blocks the panel and spends no retry.
        @Test func aRevokedGrantRefusesTheRetryAndBlocksThePanel() throws {
            begin(.authorized)
            let generation = try #require(provider.sessionGenerationForTesting)
            readStatus = .denied

            #expect(provider.claimRetries(["a"], generation: generation) == [])
            #expect(reads == 1)
            #expect(permissionReports == [.denied])
        }

        @Test func aWindowOutsideTheSessionGetsNoRetry() throws {
            begin(.authorized)
            let generation = try #require(provider.sessionGenerationForTesting)

            // "a" is not a capture request (no live window), so the ledger never
            // registered it; only registered windows may retry
            #expect(provider.claimRetries(["a"], generation: generation) == [])
            #expect(reads == 1)
            #expect(permissionReports.isEmpty)
        }
    }
}
