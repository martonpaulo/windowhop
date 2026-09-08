import XCTest
@testable import WindowHopCore

/// Registering a bare `swift build` executable at login makes launchd open a
/// terminal window on the next login. These drive the real decision with a
/// substituted ServiceManagement boundary, so no automated run can touch the
/// machine's actual login items.
final class LoginItemTests: XCTestCase {
    private final class Recorder {
        var registers = 0
        var unregisters = 0
        var enabled = false
        var registerError: Error?
    }

    private struct Failure: Error {}

    private func service(_ recorder: Recorder) -> LoginItem.Service {
        LoginItem.Service(
            isEnabled: { recorder.enabled },
            register: {
                if let error = recorder.registerError { throw error }
                recorder.registers += 1
                recorder.enabled = true
            },
            unregister: {
                recorder.unregisters += 1
                recorder.enabled = false
            })
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
        try (["CFBundleIdentifier": "com.perso.windowhop.fixture",
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
        XCTAssertTrue(LoginItem.isBundledApplication(bundledApp))
    }

    func testEnablingOutsideABundleRegistersNothing() {
        let recorder = Recorder()

        let succeeded = LoginItem.set(true, bundle: bareExecutable, service: service(recorder))

        XCTAssertFalse(succeeded)
        XCTAssertEqual(recorder.registers, 0)
    }

    /// Even if the boundary claims it is already enabled, the unbundled build
    /// must not report success — that is how the stale registration hides.
    func testUnbundledEnableFailsEvenWhenReportedEnabled() {
        let recorder = Recorder()
        recorder.enabled = true

        XCTAssertFalse(LoginItem.set(true, bundle: bareExecutable, service: service(recorder)))
        XCTAssertEqual(recorder.registers, 0)
    }

    /// Removing an earlier registration must keep working outside a bundle.
    func testDisablingOutsideABundleStillUnregisters() {
        let recorder = Recorder()
        recorder.enabled = true

        let succeeded = LoginItem.set(false, bundle: bareExecutable, service: service(recorder))

        XCTAssertTrue(succeeded)
        XCTAssertEqual(recorder.unregisters, 1)
    }

    func testEnablingFromAnApplicationBundleRegistersOnce() {
        let recorder = Recorder()

        XCTAssertTrue(LoginItem.set(true, bundle: bundledApp, service: service(recorder)))
        XCTAssertEqual(recorder.registers, 1)
    }

    func testRegistrationErrorIsReportedAsFailure() {
        let recorder = Recorder()
        recorder.registerError = Failure()

        XCTAssertFalse(LoginItem.set(true, bundle: bundledApp, service: service(recorder)))
    }

    func testAlreadyMatchingStateIsANoOp() {
        let recorder = Recorder()
        recorder.enabled = true

        XCTAssertTrue(LoginItem.set(false, bundle: bareExecutable, service: service(recorder)))
        recorder.enabled = false
        XCTAssertTrue(LoginItem.set(false, bundle: bareExecutable, service: service(recorder)))
        XCTAssertEqual(recorder.unregisters, 1, "the second call must do nothing")
    }

    func testBundleRecognitionRejectsAPlainDirectory() {
        XCTAssertFalse(LoginItem.isBundledApplication(bareExecutable))
    }
}
