import AppKit
import Sparkle

/// Sparkle 2 wrapper. Update checks are WindowHop's only routine network
/// activity — no telemetry, no analytics, no accounts. The standard Sparkle
/// UI handles the whole experience (prompt with the new version, install,
/// remind-later, skip-this-version — so the same version never nags twice);
/// the updater only starts from a real app bundle (development builds run
/// without it). The Settings Updates pane additionally mirrors the latest
/// known available version, observed through the updater delegate.
public final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = UpdateManager()

    private var controller: SPUStandardUpdaterController?

    /// The newest version the appcast offered, when newer than the running
    /// one; nil while up to date. Set from Sparkle's scheduled background
    /// checks and manual ones alike — check failures just leave it unchanged
    /// and never block anything.
    @Published public private(set) var availableVersion: String?

    override private init() {}

    public var isAvailable: Bool { controller != nil }

    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Requires the Info.plist SUFeedURL/SUPublicEDKey, so only a bundled,
    /// properly configured WindowHop.app starts the updater.
    public func startIfBundled() {
        guard controller == nil,
              Bundle.main.bundleIdentifier == "com.perso.windowhop",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        controller?.updater.automaticallyChecksForUpdates =
            Preferences.shared.automaticUpdateChecks
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    public var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - SPUUpdaterDelegate (main thread, per Sparkle 2)

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
    }
}
