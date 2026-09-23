import Foundation
import WindowHopKit

/// Coordinates Restore Defaults with the one reset preference that is also
/// applied outside UserDefaults (Sparkle's automatic update checks). Launch at
/// login is not reset: it mirrors a macOS login-item registration.
@MainActor
public struct SettingsDefaultsRestorer {
    private let preferences: Preferences
    private let applyAutomaticUpdateChecks: (Bool) -> Void

    public init(preferences: Preferences,
         applyAutomaticUpdateChecks: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.applyAutomaticUpdateChecks = applyAutomaticUpdateChecks
    }

    public func restore() {
        preferences.restoreDefaults()
        applyAutomaticUpdateChecks(Preferences.Defaults.automaticUpdateChecks)
    }
}
