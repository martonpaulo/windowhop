import AppKit
import Sparkle
import WindowHopKit

/// Sparkle 2 wrapper. Update checks are WindowHop's only routine network
/// activity — no telemetry, no analytics, no accounts. The standard Sparkle
/// UI handles the whole experience (prompt with the new version, install,
/// remind-later, skip-this-version — so the same version never nags twice);
/// the updater only starts from a real app bundle (development builds run
/// without it). The Settings Updates pane additionally mirrors the latest
/// known available version, observed through the updater delegate.
@MainActor
@Observable
public final class UpdateManager: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private let preferences: Preferences
    private var controller: SPUStandardUpdaterController?

    /// The newest version the appcast offered, when newer than the running
    /// one; nil while up to date. Set from Sparkle's scheduled background
    /// checks and manual ones alike — check failures just leave it unchanged
    /// and never block anything.
    public private(set) var availableVersion: String?

    /// Owned by `AppDelegate`; the debug harness and tests build one that is
    /// never started, which is exactly a development build's updater.
    public init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    public var isAvailable: Bool { controller != nil }

    /// Whether a user-initiated check can start right now. Sparkle reports
    /// false while a check or an update session is already in progress.
    public var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Requires a real application bundle and the Info.plist SUFeedURL/SUPublicEDKey,
    /// so only a bundled, properly configured WindowHop.app starts the updater.
    public func startIfBundled() {
        guard controller == nil,
              AppBundle.isApplication(.main),
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        controller?.updater.automaticallyChecksForUpdates =
            preferences.automaticUpdateChecks
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
