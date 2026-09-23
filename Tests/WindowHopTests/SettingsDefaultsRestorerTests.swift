import Foundation
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    @MainActor
    struct SettingsDefaultsRestorerTests {
        @Test func restoreAppliesPersistedDefaultsAndUpdateChecksButLeavesLaunchAtLogin() throws {
            let suite = "windowhop-tests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = Preferences(defaults: defaults)
            preferences.launchAtLogin = !Preferences.Defaults.launchAtLogin
            preferences.shortcut = .controlTab
            preferences.persistentShortcut = nil
            preferences.showTabCounts = true
            preferences.automaticUpdateChecks = false
            var updateValue: Bool?
            let restorer = SettingsDefaultsRestorer(
                preferences: preferences,
                applyAutomaticUpdateChecks: { updateValue = $0 })

            restorer.restore()

            #expect(updateValue == Preferences.Defaults.automaticUpdateChecks)
            #expect(preferences.launchAtLogin == !Preferences.Defaults.launchAtLogin)
            #expect(preferences.shortcut == .commandTab)
            #expect(preferences.persistentShortcut == .optionTab)
            #expect(!preferences.showTabCounts)
            #expect(preferences.automaticUpdateChecks)
            let restored = Preferences(defaults: defaults)
            #expect(restored.launchAtLogin == !Preferences.Defaults.launchAtLogin)
            #expect(restored.persistentShortcut == .optionTab)
            #expect(!restored.showTabCounts)
        }
    }
}
