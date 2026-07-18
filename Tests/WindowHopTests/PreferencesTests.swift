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
        XCTAssertEqual(preferences.navigationPreviewDelay, .standard)
        XCTAssertEqual(preferences.navigationPreviewDelay.duration, 0.7)
        XCTAssertTrue(preferences.includeOtherSpaces)
        XCTAssertTrue(preferences.includeOtherDisplays)
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
        preferences.navigationPreviewDelay = .long
        preferences.includeOtherSpaces = false
        preferences.includeOtherDisplays = false
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
        XCTAssertEqual(restored.navigationPreviewDelay, .long)
        XCTAssertFalse(restored.includeOtherSpaces)
        XCTAssertFalse(restored.includeOtherDisplays)
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
        XCTAssertEqual(migrated.navigationPreviewDelay, .standard,
                       "existing users inherit the documented 700 ms default")
        XCTAssertFalse(migrated.showTabCounts)
        XCTAssertTrue(migrated.showMenuBarItem)
    }

    func testCorruptShortcutFallsBackToCommandTab() {
        defaults.set("garbage", forKey: Preferences.Key.shortcut.rawValue)
        XCTAssertEqual(Preferences(defaults: defaults).shortcut, .commandTab)
    }

    func testCorruptAppearanceAndBooleanValuesFallBackToDocumentedDefaults() {
        defaults.set("obsolete-mode", forKey: Preferences.Key.appearanceMode.rawValue)
        defaults.set("obsolete-delay", forKey: Preferences.Key.navigationPreviewDelay.rawValue)
        defaults.set("not-a-boolean", forKey: Preferences.Key.includeOtherSpaces.rawValue)
        defaults.set("not-a-boolean", forKey: Preferences.Key.showMenuBarItem.rawValue)

        let restored = Preferences(defaults: defaults)

        XCTAssertEqual(restored.appearanceMode, .appIcons)
        XCTAssertEqual(restored.navigationPreviewDelay, .standard)
        XCTAssertTrue(restored.includeOtherSpaces)
        XCTAssertFalse(restored.showMenuBarItem)
    }

    func testCorruptPersistentShortcutRestoresUnassignedDefault() {
        defaults.set("broken-shortcut", forKey: Preferences.Key.persistentShortcut.rawValue)
        XCTAssertNil(Preferences(defaults: defaults).persistentShortcut)
    }

    func testNavigationPreviewDelayPresetsAvoidRawMillisecondsInSettings() {
        XCTAssertNil(NavigationPreviewDelay.off.duration)
        XCTAssertEqual(NavigationPreviewDelay.short.duration, 0.35)
        XCTAssertEqual(NavigationPreviewDelay.standard.duration, 0.7)
        XCTAssertEqual(NavigationPreviewDelay.long.duration, 1.2)
        XCTAssertEqual(NavigationPreviewDelay.allCases.map(\.displayName),
                       ["Off", "Short", "Default", "Long"])
    }

    func testNavigationPreviewDelayPublishesRuntimeUpdatesImmediately() {
        var observed: [NavigationPreviewDelay] = []
        let observation = preferences.$navigationPreviewDelay.sink {
            observed.append($0)
        }

        preferences.navigationPreviewDelay = .short

        XCTAssertEqual(observed, [.standard, .short])
        withExtendedLifetime(observation) {}
    }
}
