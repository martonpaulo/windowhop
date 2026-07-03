import XCTest
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
        XCTAssertTrue(preferences.includeOtherSpaces)
        XCTAssertTrue(preferences.includeOtherDisplays)
        XCTAssertTrue(preferences.showTabCounts)
        XCTAssertFalse(preferences.showMenuBarItem)
        XCTAssertFalse(preferences.showDockIcon)
        XCTAssertFalse(preferences.firstLaunchCompleted)
    }

    func testRoundTrip() {
        preferences.switcherEnabled = false
        preferences.shortcut = .optionTab
        preferences.showMenuBarItem = true
        XCTAssertFalse(preferences.switcherEnabled)
        XCTAssertEqual(preferences.shortcut, .optionTab)
        XCTAssertTrue(preferences.showMenuBarItem)
    }

    func testCorruptShortcutFallsBackToCommandTab() {
        defaults.set("garbage", forKey: Preferences.Key.shortcut.rawValue)
        XCTAssertEqual(preferences.shortcut, .commandTab)
    }
}
