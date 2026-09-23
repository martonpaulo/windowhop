import Foundation

@testable import WindowHopCore
@testable import WindowHopKit

/// A `Preferences` over its own throwaway `UserDefaults` suite, so a test never
/// reads or changes the developer's real settings. Call `remove()` in tearDown.
@MainActor
final class IsolatedPreferences {
    let suiteName = "windowhop-tests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let preferences: Preferences
    /// A preview cache of its own, so no test sees another test's images.
    let previews: PreviewProvider

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        preferences = Preferences(defaults: defaults)
        previews = PreviewProvider(preferences: preferences)
    }

    /// Settings content over these preferences, with an updater that is never
    /// started, as in any development build.
    var settingsDependencies: SettingsDependencies {
        SettingsDependencies(
            preferences: preferences,
            restorer: SettingsDefaultsRestorer(
                preferences: preferences,
                applyAutomaticUpdateChecks: { _ in }),
            updateManager: UpdateManager(preferences: preferences),
            setShortcutRecordingActive: { _ in },
            evictPreviews: {})
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
