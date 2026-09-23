import AppKit
import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// The Screen Recording preflight costs 14–18 ms on the main thread (#120).
/// A session reads it once when it opens; windows that join reuse that read,
/// and only a capture failure reads it again, so a revoked grant still reaches
/// the permission-blocked presentation (#51).
@MainActor
final class PreviewSessionPermissionTests: XCTestCase {
    private var savedAppearanceMode: AppearanceMode!
    private var savedPermissionRequired: ((ScreenRecordingPermission.Status) -> Void)?
    private var savedUnavailable: ((AnyHashable) -> Void)?
    private var reads = 0
    private var readStatus: ScreenRecordingPermission.Status = .authorized
    private var permissionReports: [ScreenRecordingPermission.Status] = []

    private var provider: PreviewProvider { PreviewProvider.shared }

    override func setUp() async throws {
        try await super.setUp()
        savedAppearanceMode = Preferences.shared.appearanceMode
        Preferences.shared.appearanceMode = .windowPreviews
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

    override func tearDown() async throws {
        provider.endSession()
        provider.readPermissionStatus = { ScreenRecordingPermission.status }
        provider.onPermissionRequired = savedPermissionRequired
        provider.onPreviewUnavailable = savedUnavailable
        Preferences.shared.appearanceMode = savedAppearanceMode
        try await super.tearDown()
    }

    /// Items without a live window make no capture request, so no real
    /// screenshot or shareable-content lookup is ever started.
    private func items(_ ids: [String]) -> [SwitcherItem] {
        ids.map {
            SwitcherItem(id: $0, window: nil, title: "Window \($0)",
                         appName: "TestApp", icon: nil, tabCount: nil)
        }
    }

    private func begin(_ status: ScreenRecordingPermission.Status) {
        provider.beginSession(items: items(["a"]), targetSize: CGSize(width: 100, height: 60),
                              scale: 2, permissionStatus: status)
    }

    private func join(_ ids: [String]) {
        provider.extendSession(items: items(ids), targetSize: CGSize(width: 100, height: 60),
                               scale: 2)
    }

    func testJoiningWindowsReuseTheSessionStatus() {
        begin(.authorized)
        for batch in 0..<10 { join(["join-\(batch)"]) }

        XCTAssertEqual(reads, 0, "a joining window must not read the permission again")
        XCTAssertEqual(provider.sessionPermissionForTesting, .authorized)
    }

    func testABlockedSessionReportsTheStatusItWasOpenedWith() {
        begin(.denied)

        XCTAssertEqual(permissionReports, [.denied])
        XCTAssertEqual(reads, 0)
        XCTAssertNil(provider.sessionPermissionForTesting, "a blocked session captures nothing")
    }

    /// The #51 presentation still follows a real change: a failure batch reads
    /// the status once and a revoked grant blocks the panel.
    func testAFailureAfterARevokedGrantBlocksThePanelOnce() throws {
        begin(.authorized)
        let generation = try XCTUnwrap(provider.sessionGenerationForTesting)
        readStatus = .denied

        provider.markUnavailable(["a", "b", "c"], generation: generation)

        XCTAssertEqual(reads, 1, "one read per failure batch, not one per window")
        XCTAssertEqual(permissionReports, [.denied])
        XCTAssertEqual(provider.sessionPermissionForTesting, .denied)

        provider.markUnavailable(["d"], generation: generation)
        join(["late"])
        XCTAssertEqual(reads, 1, "a session already blocked does not read again")
        XCTAssertEqual(permissionReports, [.denied])
    }

    func testAFailureWithTheGrantIntactKeepsTheSessionAuthorized() throws {
        begin(.authorized)
        let generation = try XCTUnwrap(provider.sessionGenerationForTesting)

        provider.markUnavailable(["a", "b"], generation: generation)

        XCTAssertEqual(reads, 1)
        XCTAssertTrue(permissionReports.isEmpty)
        XCTAssertEqual(provider.sessionPermissionForTesting, .authorized)
    }

    func testAFailureFromAnEndedSessionReadsNothing() throws {
        begin(.authorized)
        let generation = try XCTUnwrap(provider.sessionGenerationForTesting)
        provider.endSession()
        readStatus = .denied

        provider.markUnavailable(["a"], generation: generation)

        XCTAssertEqual(reads, 0)
        XCTAssertTrue(permissionReports.isEmpty)
    }

    // MARK: - Retry allowance (#91)

    /// A retry is failure-driven work, so it confirms the grant once for the
    /// batch: a revoked grant blocks the panel and spends no retry.
    func testARevokedGrantRefusesTheRetryAndBlocksThePanel() throws {
        begin(.authorized)
        let generation = try XCTUnwrap(provider.sessionGenerationForTesting)
        readStatus = .denied

        XCTAssertEqual(provider.claimRetries(["a"], generation: generation), [])
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(permissionReports, [.denied])
    }

    func testAWindowOutsideTheSessionGetsNoRetry() throws {
        begin(.authorized)
        let generation = try XCTUnwrap(provider.sessionGenerationForTesting)

        // "a" is not a capture request (no live window), so the ledger never
        // registered it; only registered windows may retry
        XCTAssertEqual(provider.claimRetries(["a"], generation: generation), [])
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(permissionReports.isEmpty)
    }
}
