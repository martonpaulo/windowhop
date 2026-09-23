import Foundation
import ServiceManagement
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

/// Registering a bare `swift build` executable at login makes launchd open a
/// terminal window on the next login. These drive the real decision with a
/// substituted ServiceManagement boundary, so no automated run can touch the
/// machine's actual login items.
final class LoginItemTests {
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

    init() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LoginItemTests-\(UUID().uuidString)")
        let appURL = temporaryDirectory.appendingPathComponent("WindowHopFixture.app")
        let contents = appURL.appendingPathComponent("Contents")
        let plainURL = temporaryDirectory.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plainURL, withIntermediateDirectories: true)
        try
            ([
                "CFBundleIdentifier": "test.windowhop.fixture",
                "CFBundleName": "WindowHopFixture",
                "CFBundlePackageType": "APPL",
            ] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"))
        // unwrapped into locals: assigned straight to the implicitly unwrapped
        // properties, #require would infer an optional result and never fail
        let app = try #require(Bundle(url: appURL))
        let bare = try #require(Bundle(url: plainURL))
        bundledApp = app
        bareExecutable = bare
    }

    deinit {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    @Test func theSyntheticAppBundleIsRecognized() {
        #expect(AppBundle.isApplication(bundledApp))
    }

    @Test func bundleRecognitionRejectsAPlainDirectory() {
        #expect(!AppBundle.isApplication(bareExecutable))
    }

    // MARK: Status

    @Test func everyServiceStatusMapsForABundledApp() {
        #expect(LoginItem.status(.enabled, bundled: true) == .enabled)
        #expect(LoginItem.status(.notRegistered, bundled: true) == .disabled)
        #expect(LoginItem.status(.requiresApproval, bundled: true) == .requiresApproval)
        // a never-registered bundle reads notFound on macOS 26; it must stay
        // enableable rather than lock the toggle
        #expect(LoginItem.status(.notFound, bundled: true) == .disabled)
    }

    @Test func anUnregisteredBareExecutableIsUnavailable() {
        #expect(LoginItem.status(.notRegistered, bundled: false) == .unavailable)
        #expect(LoginItem.status(.notFound, bundled: false) == .unavailable)
    }

    /// An old registration of a bare build is shown, so it can be removed.
    @Test func aRegisteredBareExecutableShowsItsRegistration() {
        #expect(LoginItem.status(.enabled, bundled: false) == .enabled)
        #expect(LoginItem.status(.requiresApproval, bundled: false) == .requiresApproval)
    }

    // MARK: Changes

    @Test func enablingReadsTheResultingStatus() {
        let recorder = Recorder()

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .enabled, failed: false))
        #expect(recorder.registers == 1)
    }

    @Test func registrationAwaitingApprovalIsNotReportedAsEnabled() {
        let recorder = Recorder()
        recorder.statusAfterRegister = .requiresApproval

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .requiresApproval, failed: false))
    }

    /// `register()` throws while macOS holds the item for approval: the
    /// person must see the approval state, not a generic failure.
    @Test func throwingRegistrationAwaitingApprovalShowsTheApprovalState() {
        let recorder = Recorder()
        recorder.statusAfterRegister = .requiresApproval
        recorder.registerError = Failure()

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .requiresApproval, failed: false))
    }

    @Test func throwingRegistrationThatLeavesNothingRegisteredFails() {
        let recorder = Recorder()
        recorder.statusAfterRegister = .notRegistered
        recorder.registerError = Failure()

        let change = LoginItem.set(true, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .disabled, failed: true))
    }

    @Test func disablingReadsTheResultingStatus() {
        let recorder = Recorder()
        recorder.status = .enabled

        let change = LoginItem.set(false, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .disabled, failed: false))
        #expect(recorder.unregisters == 1)
    }

    @Test func disablingWhileAwaitingApprovalUnregisters() {
        let recorder = Recorder()
        recorder.status = .requiresApproval

        let change = LoginItem.set(false, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .disabled, failed: false))
        #expect(recorder.unregisters == 1)
    }

    @Test func failedUnregistrationKeepsTheRegistrationVisible() {
        let recorder = Recorder()
        recorder.status = .enabled
        recorder.unregisterError = Failure()

        let change = LoginItem.set(false, bundle: bundledApp, service: service(recorder))

        #expect(change == LoginItemChange(status: .enabled, failed: true))
    }

    @Test func alreadyMatchingStateIsANoOp() {
        let recorder = Recorder()

        #expect(
            LoginItem.set(false, bundle: bundledApp, service: service(recorder))
                == LoginItemChange(status: .disabled, failed: false))
        recorder.status = .requiresApproval
        #expect(
            LoginItem.set(true, bundle: bundledApp, service: service(recorder))
                == LoginItemChange(status: .requiresApproval, failed: false))
        #expect(recorder.registers + recorder.unregisters == 0)
    }

    // MARK: The bundle guard (#14)

    @Test func enablingOutsideABundleRegistersNothing() {
        let recorder = Recorder()

        let change = LoginItem.set(true, bundle: bareExecutable, service: service(recorder))

        #expect(change == LoginItemChange(status: .unavailable, failed: true))
        #expect(recorder.registers == 0)
    }

    /// Even if the boundary claims it is already enabled, the unbundled build
    /// must not report success — that is how the stale registration hides.
    @Test func unbundledEnableFailsEvenWhenReportedEnabled() {
        let recorder = Recorder()
        recorder.status = .enabled

        #expect(LoginItem.set(true, bundle: bareExecutable, service: service(recorder)).failed)
        #expect(recorder.registers == 0)
    }

    /// Removing an earlier registration must keep working outside a bundle.
    @Test func disablingOutsideABundleStillUnregisters() {
        let recorder = Recorder()
        recorder.status = .enabled

        let change = LoginItem.set(false, bundle: bareExecutable, service: service(recorder))

        #expect(change == LoginItemChange(status: .unavailable, failed: false))
        #expect(recorder.unregisters == 1)
    }
}
