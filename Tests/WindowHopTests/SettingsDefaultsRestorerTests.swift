import XCTest
@testable import WindowHopCore

final class SettingsDefaultsRestorerTests: XCTestCase {
    func testExternalFailureLeavesEveryPreferenceUntouched() {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.shortcut = .controlTab
        preferences.showTabCounts = true
        preferences.automaticUpdateChecks = false
        var appliedUpdateValue: Bool?
        let restorer = SettingsDefaultsRestorer(
            preferences: preferences,
            setLoginItem: { _ in false },
            applyAutomaticUpdateChecks: { appliedUpdateValue = $0 })

        XCTAssertFalse(restorer.restore())
        XCTAssertEqual(preferences.shortcut, .controlTab)
        XCTAssertTrue(preferences.showTabCounts)
        XCTAssertFalse(preferences.automaticUpdateChecks)
        XCTAssertNil(appliedUpdateValue)
    }

    func testSuccessfulRestoreAppliesExternalAndPersistedDefaultsTogether() {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.shortcut = .controlTab
        preferences.persistentShortcut = nil
        preferences.showTabCounts = true
        preferences.automaticUpdateChecks = false
        var loginValue: Bool?
        var updateValue: Bool?
        let restorer = SettingsDefaultsRestorer(
            preferences: preferences,
            setLoginItem: { loginValue = $0; return true },
            applyAutomaticUpdateChecks: { updateValue = $0 })

        XCTAssertTrue(restorer.restore())
        XCTAssertEqual(loginValue, Preferences.Defaults.launchAtLogin)
        XCTAssertEqual(updateValue, Preferences.Defaults.automaticUpdateChecks)
        XCTAssertEqual(preferences.shortcut, .commandTab)
        XCTAssertEqual(preferences.persistentShortcut, .optionTab)
        XCTAssertFalse(preferences.showTabCounts)
        XCTAssertTrue(preferences.automaticUpdateChecks)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.persistentShortcut, .optionTab)
        XCTAssertFalse(restored.showTabCounts)
    }
}
