import Foundation

/// Coordinates Restore Defaults with the one reset preference that is also
/// applied outside UserDefaults (Sparkle's automatic update checks). Launch at
/// login is not reset: it mirrors a macOS login-item registration.
public struct SettingsDefaultsRestorer {
    private let preferences: Preferences
    private let applyAutomaticUpdateChecks: (Bool) -> Void

    public static let shared = SettingsDefaultsRestorer(
        preferences: .shared,
        applyAutomaticUpdateChecks: {
            UpdateManager.shared.automaticallyChecksForUpdates = $0
        })

    init(preferences: Preferences,
         applyAutomaticUpdateChecks: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.applyAutomaticUpdateChecks = applyAutomaticUpdateChecks
    }

    public func restore() {
        preferences.restoreDefaults()
        applyAutomaticUpdateChecks(Preferences.Defaults.automaticUpdateChecks)
    }
}
