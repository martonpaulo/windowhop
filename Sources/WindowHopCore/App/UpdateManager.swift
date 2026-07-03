import AppKit
import Sparkle

/// Sparkle 2 wrapper. Update checks are WindowHop's only routine network
/// activity — no telemetry, no analytics, no accounts. The standard Sparkle
/// UI handles the whole experience; the updater only starts from a real app
/// bundle (development builds run without it).
public final class UpdateManager {
    public static let shared = UpdateManager()

    private var controller: SPUStandardUpdaterController?

    private init() {}

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
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    public var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
