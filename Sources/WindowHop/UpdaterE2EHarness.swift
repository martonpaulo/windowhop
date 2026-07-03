import AppKit
import Sparkle

/// Headless end-to-end updater exercise, reachable only via
/// `--updater-e2e <feed-url>`. Drives a real SPUUpdater with an auto-accepting
/// user driver against a local appcast, so update detection, version comparison,
/// EdDSA verification, download, install, and relaunch are genuinely tested.
///
/// Exit codes: Sparkle terminates the process itself on successful install;
/// 2 = updater error (e.g. invalid signature), 3 = no update found.
enum UpdaterE2EHarness {
    private static var updater: SPUUpdater?
    private static var driver: AutoAcceptDriver?
    private static var delegate: FeedDelegate?

    static func run(feedURL: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let driver = AutoAcceptDriver()
        let delegate = FeedDelegate(feed: feedURL)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                 userDriver: driver, delegate: delegate)
        self.driver = driver
        self.delegate = delegate
        self.updater = updater
        DispatchQueue.main.async {
            do {
                try updater.start()
            } catch {
                print("E2E: updater failed to start: \(error)")
                exit(4)
            }
            print("E2E: checking \(feedURL) from version "
                + "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") "
                + "(build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"))")
            updater.checkForUpdates()
        }
        // safety net: a hung updater must not leave a zombie process around
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            print("E2E: timed out")
            exit(5)
        }
        app.run()
    }
}

private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
    let feed: String

    init(feed: String) {
        self.feed = feed
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feed
    }
}

private final class AutoAcceptDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        print("E2E: user-initiated check started")
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("E2E: update found: version \(appcastItem.displayVersionString) "
            + "(build \(appcastItem.versionString)), installing")
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("E2E: no update found")
        acknowledgement()
        exit(3)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("E2E: updater error: \((error as NSError).localizedDescription)")
        if let reason = (error as NSError).localizedFailureReason {
            print("E2E: reason: \(reason)")
        }
        acknowledgement()
        exit(2)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        print("E2E: download started")
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        print("E2E: extracting (archive accepted)")
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("E2E: ready to install, relaunching")
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        print("E2E: installing (terminated=\(applicationTerminated))")
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        print("E2E: installed and relaunched=\(relaunched)")
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        print("E2E: installation UI dismissed")
    }
}
