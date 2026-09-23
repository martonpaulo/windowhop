import ServiceManagement
import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// Registering a bare `swift build` executable at login makes launchd open a
/// terminal window on the next login. These drive the real decision with a
/// substituted ServiceManagement boundary, so no automated run can touch the
/// machine's actual login items.
final class LoginItemTests: XCTestCase {
    private final class Recorder {
        var registers = 0
        var unregisters = 0
        var status: SMAppService.Status = .notRegistered
        /// What `register()` leaves behind: approved, or waiting for approval.
        var statusAfterRegister: SMAppService.Status = .enabled
        var registerError: Error?
        var unregisterError: Error?
    }

    private struct Failure: Error {}

    private func service(_ recorder: Recorder) -> LoginItem.Service {
        LoginItem.Service(
            status: { recorder.status },
            register: {
                recorder.registers += 1
                recorder.status = recorder.statusAfterRegister
                if let error = recorder.registerError { throw error }
            },
            unregister: {
                recorder.unregisters += 1
                if let error = recorder.unregisterError { throw error }
                recorder.status = .notRegistered
            },
            openLoginItemsSettings: {})
    }

    private var temporaryDirectory: URL!
    /// A synthetic `.app` with an Info.plist, so the positive path is really
    /// exercised instead of skipped when the runner is not itself an app.
    private var bundledApp: Bundle!
    /// A plain directory: what `swift build` produces and runs from a terminal.
    private var bareExecutable: Bundle!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LoginItemTests-\(UUID().uuidString)")
        let appURL = temporaryDirectory.appendingPathComponent("WindowHopFixture.app")
        let contents = appURL.appendingPathComponent("Contents")
        let plainURL = temporaryDirectory.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plainURL, withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "test.windowhop.fixture",
              "CFBundleName": "WindowHopFixture",
              "CFBundlePackageType": "APPL"] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"))
        bundledApp = try XCTUnwrap(Bundle(url: appURL))
        bareExecutable = try XCTUnwrap(Bundle(url: plainURL))
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testTheSyntheticAppBundleIsRecognized() {
        XCTAssertTrue(AppBundle.isApplication(bundledApp))
    }

    func testBundleRecognitionRejectsAPlainDirectory() {
        XCTAssertFalse(AppBundle.isApplication(bareExecutable))
    }

    // MARK: Status

    func testEveryServiceStatusMapsForABundledApp() {
        XCTAssertEqual(LoginItem.status(.enabled, bundled: true), .enabled)
        XCTAssertEqual(LoginItem.status(.notRegistered, bundled: true), .disabled)
        XCTAssertEqual(LoginItem.status(.requiresApproval, bundled: true), .requiresApproval)
        // a never-registered bundle reads notFound on macOS 26; it must stay
        // enableable rather than lock the toggle
        XCTAssertEqual(LoginItem.status(.notFound, bundled: true), .disabled)
    }

    func testAnUnregisteredBareExecutableIsUnavailable() {
        XCTAssertEqual(LoginItem.status(.notRegistered, bundled: false), .unavailable)
        XCTAssertEqual(LoginItem.status(.notFound, bundled: false), .unavailable)
    }

    /// An old registration of a bare build is shown, so it can be removed.
    func testARegisteredBareExecutableShowsItsRegistration() {
        XCTAssertEqual(LoginItem.status(.enabled, bundled: false), .enabled)
        XCTAssertEqual(LoginItem.status(.requiresApproval, bundled: false), .requiresApproval)
    }

    // MARK: Changes

    func testEnablingReadsTheResultingStatus() {
        let recorder = Recorder()

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .enabled, failed: false))
        XCTAssertEqual(recorder.registers, 1)
    }

    func testRegistrationAwaitingApprovalIsNotReportedAsEnabled() {
        let recorder = Recorder()
        recorder.statusAfterRegister = .requiresApproval

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .requiresApproval, failed: false))
    }

    /// `register()` throws while macOS holds the item for approval: the
    /// person must see the approval state, not a generic failure.
    func testThrowingRegistrationAwaitingApprovalShowsTheApprovalState() {
        let recorder = Recorder()
        recorder.statusAfterRegister = .requiresApproval
        recorder.registerError = Failure()

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .requiresApproval, failed: false))
    }

    func testThrowingRegistrationThatLeavesNothingRegisteredFails() {
        let recorder = Recorder()
        recorder.statusAfterRegister = .notRegistered
        recorder.registerError = Failure()

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .disabled, failed: true))
    }

    func testDisablingReadsTheResultingStatus() {
        let recorder = Recorder()
        recorder.status = .enabled

        let change = LoginItem.set(false, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .disabled, failed: false))
        XCTAssertEqual(recorder.unregisters, 1)
    }

    func testDisablingWhileAwaitingApprovalUnregisters() {
        let recorder = Recorder()
        recorder.status = .requiresApproval

        let change = LoginItem.set(false, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .disabled, failed: false))
        XCTAssertEqual(recorder.unregisters, 1)
    }

    func testFailedUnregistrationKeepsTheRegistrationVisible() {
        let recorder = Recorder()
        recorder.status = .enabled
        recorder.unregisterError = Failure()

        let change = LoginItem.set(false, bundle: bundledApp, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .enabled, failed: true))
    }

    func testAlreadyMatchingStateIsANoOp() {
        let recorder = Recorder()

        XCTAssertEqual(LoginItem.set(false, bundle: bundledApp, service: service(recorder)),
                       LoginItemChange(status: .disabled, failed: false))
        recorder.status = .requiresApproval
        XCTAssertEqual(LoginItem.set(true, bundle: bundledApp, service: service(recorder)),
                       LoginItemChange(status: .requiresApproval, failed: false))
        XCTAssertEqual(recorder.registers + recorder.unregisters, 0)
    }

    // MARK: The bundle guard (#14)

    func testEnablingOutsideABundleRegistersNothing() {
        let recorder = Recorder()

        let change = LoginItem.set(true, bundle: bareExecutable, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .unavailable, failed: true))
        XCTAssertEqual(recorder.registers, 0)
    }

    /// Even if the boundary claims it is already enabled, the unbundled build
    /// must not report success — that is how the stale registration hides.
    func testUnbundledEnableFailsEvenWhenReportedEnabled() {
        let recorder = Recorder()
        recorder.status = .enabled

        XCTAssertTrue(LoginItem.set(true, bundle: bareExecutable, service: service(recorder)).failed)
        XCTAssertEqual(recorder.registers, 0)
    }

    /// Removing an earlier registration must keep working outside a bundle.
    func testDisablingOutsideABundleStillUnregisters() {
        let recorder = Recorder()
        recorder.status = .enabled

        let change = LoginItem.set(false, bundle: bareExecutable, service: service(recorder))

        XCTAssertEqual(change, LoginItemChange(status: .unavailable, failed: false))
        XCTAssertEqual(recorder.unregisters, 1)
    }
}
