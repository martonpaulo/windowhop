import XCTest
import Combine
@testable import WindowHopCore

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!

    override func setUp() {
        super.setUp()
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = Preferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaults() {
        XCTAssertTrue(preferences.switcherEnabled)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertEqual(preferences.shortcut, .commandTab)
        XCTAssertNil(preferences.persistentShortcut)
        XCTAssertEqual(preferences.appearanceMode, .appIcons)
        XCTAssertEqual(preferences.expandedPreviewDelay, .threeSeconds)
        XCTAssertEqual(preferences.expandedPreviewDelay.duration, 3)
        XCTAssertTrue(preferences.includeOtherSpaces)
        XCTAssertTrue(preferences.includeOtherDisplays)
        XCTAssertFalse(preferences.includeMinimizedWindows)
        XCTAssertFalse(preferences.includeHiddenApplicationWindows)
        XCTAssertFalse(preferences.includePictureInPictureWindows)
        XCTAssertTrue(preferences.showTabCounts)
        XCTAssertFalse(preferences.showMenuBarItem)
        XCTAssertFalse(preferences.showDockIcon)
        XCTAssertFalse(preferences.firstLaunchCompleted)
    }

    func testRoundTrip() {
        preferences.switcherEnabled = false
        preferences.launchAtLogin = false
        preferences.shortcut = .optionTab
        preferences.persistentShortcut = PersistentShortcut(
            keyCode: KeyCode.space, modifiers: [.maskAlternate])
        preferences.appearanceMode = .windowPreviews
        preferences.expandedPreviewDelay = .fiveSeconds
        preferences.includeOtherSpaces = false
        preferences.includeOtherDisplays = false
        preferences.includeMinimizedWindows = true
        preferences.includeHiddenApplicationWindows = true
        preferences.includePictureInPictureWindows = true
        preferences.showTabCounts = false
        preferences.showMenuBarItem = true
        preferences.showDockIcon = true
        preferences.firstLaunchCompleted = true

        let restored = Preferences(defaults: defaults)

        XCTAssertFalse(restored.switcherEnabled)
        XCTAssertFalse(restored.launchAtLogin)
        XCTAssertEqual(restored.shortcut, .optionTab)
        XCTAssertEqual(restored.persistentShortcut, preferences.persistentShortcut)
        XCTAssertEqual(restored.appearanceMode, .windowPreviews)
        XCTAssertEqual(restored.expandedPreviewDelay, .fiveSeconds)
        XCTAssertFalse(restored.includeOtherSpaces)
        XCTAssertFalse(restored.includeOtherDisplays)
        XCTAssertTrue(restored.includeMinimizedWindows)
        XCTAssertTrue(restored.includeHiddenApplicationWindows)
        XCTAssertTrue(restored.includePictureInPictureWindows)
        XCTAssertFalse(restored.showTabCounts)
        XCTAssertTrue(restored.showMenuBarItem)
        XCTAssertTrue(restored.showDockIcon)
        XCTAssertTrue(restored.firstLaunchCompleted)
    }

    func testLoadsValuesPersistedByEarlierVersionsWithoutDataLoss() {
        let openShortcut = PersistentShortcut(
            keyCode: KeyCode.space, modifiers: [.maskAlternate])
        defaults.set(false, forKey: Preferences.Key.switcherEnabled.rawValue)
        defaults.set(ShortcutSpec.optionTab.rawValue,
                     forKey: Preferences.Key.shortcut.rawValue)
        defaults.set(openShortcut.encoded,
                     forKey: Preferences.Key.persistentShortcut.rawValue)
        defaults.set(AppearanceMode.windowPreviews.rawValue,
                     forKey: Preferences.Key.appearanceMode.rawValue)
        defaults.set(false, forKey: Preferences.Key.showTabCounts.rawValue)
        defaults.set(true, forKey: Preferences.Key.showMenuBarItem.rawValue)

        let migrated = Preferences(defaults: defaults)

        XCTAssertFalse(migrated.switcherEnabled)
        XCTAssertEqual(migrated.shortcut, .optionTab)
        XCTAssertEqual(migrated.persistentShortcut, openShortcut)
        XCTAssertEqual(migrated.appearanceMode, .windowPreviews)
        XCTAssertEqual(migrated.expandedPreviewDelay, .threeSeconds,
                       "existing users inherit the documented three-second default")
        XCTAssertFalse(migrated.includeMinimizedWindows)
        XCTAssertFalse(migrated.includeHiddenApplicationWindows)
        XCTAssertFalse(migrated.includePictureInPictureWindows)
        XCTAssertFalse(migrated.showTabCounts)
        XCTAssertTrue(migrated.showMenuBarItem)
    }

    func testCorruptShortcutFallsBackToCommandTab() {
        defaults.set("garbage", forKey: Preferences.Key.shortcut.rawValue)
        XCTAssertEqual(Preferences(defaults: defaults).shortcut, .commandTab)
    }

    func testCorruptAppearanceAndBooleanValuesFallBackToDocumentedDefaults() {
        defaults.set("obsolete-mode", forKey: Preferences.Key.appearanceMode.rawValue)
        defaults.set("obsolete-delay", forKey: Preferences.Key.expandedPreviewDelay.rawValue)
        defaults.set("not-a-boolean", forKey: Preferences.Key.includeOtherSpaces.rawValue)
        defaults.set("not-a-boolean",
                     forKey: Preferences.Key.includeMinimizedWindows.rawValue)
        defaults.set("not-a-boolean", forKey: Preferences.Key.showMenuBarItem.rawValue)

        let restored = Preferences(defaults: defaults)

        XCTAssertEqual(restored.appearanceMode, .appIcons)
        XCTAssertEqual(restored.expandedPreviewDelay, .threeSeconds)
        XCTAssertTrue(restored.includeOtherSpaces)
        XCTAssertFalse(restored.includeMinimizedWindows)
        XCTAssertFalse(restored.showMenuBarItem)
    }

    func testCorruptPersistentShortcutRestoresUnassignedDefault() {
        defaults.set("broken-shortcut", forKey: Preferences.Key.persistentShortcut.rawValue)
        XCTAssertNil(Preferences(defaults: defaults).persistentShortcut)
    }

    func testExpandedPreviewDelayPresetsAvoidRawMillisecondsInSettings() {
        XCTAssertNil(ExpandedPreviewDelay.off.duration)
        XCTAssertEqual(ExpandedPreviewDelay.oneSecond.duration, 1)
        XCTAssertEqual(ExpandedPreviewDelay.twoSeconds.duration, 2)
        XCTAssertEqual(ExpandedPreviewDelay.threeSeconds.duration, 3)
        XCTAssertEqual(ExpandedPreviewDelay.fiveSeconds.duration, 5)
        XCTAssertEqual(ExpandedPreviewDelay.allCases.map(\.displayName),
                       ["Off", "1 second", "2 seconds", "3 seconds", "5 seconds"])
    }

    func testExpandedPreviewDelayPublishesRuntimeUpdatesImmediately() {
        var observed: [ExpandedPreviewDelay] = []
        let observation = preferences.$expandedPreviewDelay.sink {
            observed.append($0)
        }

        preferences.expandedPreviewDelay = .oneSecond

        XCTAssertEqual(observed, [.threeSeconds, .oneSecond])
        withExtendedLifetime(observation) {}
    }

    func testLegacyNavigationDelayMigratesToExpandedPreviewPreset() {
        defaults.removeObject(forKey: Preferences.Key.expandedPreviewDelay.rawValue)
        defaults.set("long", forKey: Preferences.Key.navigationPreviewDelay.rawValue)

        XCTAssertEqual(Preferences(defaults: defaults).expandedPreviewDelay, .fiveSeconds)
    }

    func testWindowFilterChangesPublishRuntimeRefresh() {
        let expectation = expectation(forNotification: Preferences.windowFiltersDidChange,
                                      object: preferences)
        preferences.includePictureInPictureWindows = true
        wait(for: [expectation], timeout: 1)
    }
}
