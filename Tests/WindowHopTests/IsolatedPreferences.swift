import Foundation
import WindowHopTestSupport

@testable import WindowHopCore
@testable import WindowHopKit

/// A `Preferences` over its own throwaway `UserDefaults` suite, so a test never
/// reads or changes the developer's real settings. Call `remove()` in the suite's deinit.
@MainActor
final class IsolatedPreferences {
    private let suite: TestDefaults
    var defaults: UserDefaults { suite.defaults }
    let preferences: Preferences
    /// A preview cache of its own, so no test sees another test's images.
    let previews: PreviewProvider

    init() throws {
        suite = try TestDefaults()
        preferences = Preferences(defaults: suite.defaults)
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
        suite.remove()
    }
}
