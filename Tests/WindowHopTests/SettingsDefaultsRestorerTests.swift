import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

@MainActor
final class SettingsDefaultsRestorerTests: XCTestCase {
    func testRestoreAppliesPersistedDefaultsAndUpdateChecksButLeavesLaunchAtLogin() {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
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

        XCTAssertEqual(updateValue, Preferences.Defaults.automaticUpdateChecks)
        XCTAssertEqual(preferences.launchAtLogin, !Preferences.Defaults.launchAtLogin)
        XCTAssertEqual(preferences.shortcut, .commandTab)
        XCTAssertEqual(preferences.persistentShortcut, .optionTab)
        XCTAssertFalse(preferences.showTabCounts)
        XCTAssertTrue(preferences.automaticUpdateChecks)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.launchAtLogin, !Preferences.Defaults.launchAtLogin)
        XCTAssertEqual(restored.persistentShortcut, .optionTab)
        XCTAssertFalse(restored.showTabCounts)
    }
}
