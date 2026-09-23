import XCTest
@testable import WindowHopKit

/// The one-time move to versioned setting names (#111): every stored choice
/// survives, an invalid value falls back to its default, the old names are
/// removed, and a second run changes nothing.
@MainActor
final class PreferencesKeyMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    /// What this suite stores itself. `object(forKey:)` would also answer from
    /// the process-wide registration domain that any `Preferences` fills.
    private func stored(_ name: String) -> Any? {
        defaults.persistentDomain(forName: suiteName)?[name]
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// One non-default valid value and one invalid value per migrated key,
    /// under the name the key had before schema 1.
    private let samples: [(old: String, key: Preferences.Key, valid: Any, invalid: Any)] = [
        ("switcherEnabled", .switcherEnabled, false, "yes"),
        ("launchAtLogin", .launchAtLogin, true, "on"),
        ("shortcut", .shortcut, ShortcutSpec.controlTab.rawValue, "hyperTab"),
        ("persistentShortcut", .persistentShortcut, "", 42),
        ("appearanceMode", .appearanceMode, AppearanceMode.windowPreviews.rawValue, "tiles"),
        ("expandedPreviewDelay", .expandedPreviewDelay, ExpandedPreviewDelay.fiveSeconds.rawValue, "long"),
        ("switcherRevealDelay", .switcherRevealDelay, SwitcherRevealDelay.off.rawValue, "fast"),
        ("switcherDisplayPlacement", .switcherDisplayPlacement,
         SwitcherDisplayPlacement.specificDisplay.rawValue, "everywhere"),
        ("switcherDisplayID", .switcherDisplayID, "37D8832A-2D66-02CA-B9F7-8F30A301B230", 7),
        ("includeOtherSpaces", .includeOtherSpaces, false, "no"),
        ("includeOtherDisplays", .includeOtherDisplays, false, "no"),
        ("includeMinimizedWindows", .includeMinimizedWindows, true, "yes"),
        ("includeHiddenApplicationWindows", .includeHiddenApplicationWindows, true, "yes"),
        ("includePictureInPictureWindows", .includePictureInPictureWindows, true, "yes"),
        ("showTabCounts", .showTabCounts, true, "yes"),
        ("showMenuBarItem", .showMenuBarItem, true, "yes"),
        ("showDockIcon", .showDockIcon, true, "yes"),
        ("firstLaunchCompleted", .firstLaunchCompleted, true, "yes"),
    ]

    func testEveryWindowHopOwnedKeyIsVersionedAndCoveredHere() {
        let migrated = Set(PreferencesKeyMigration.renamedKeys.map(\.new))
        XCTAssertEqual(migrated, Set(samples.map(\.key)))
        for (old, key) in PreferencesKeyMigration.renamedKeys {
            XCTAssertEqual(key.rawValue, "\(old).v1")
        }
        // the two names that keep their spelling, and why, are in the migration's doc
        XCTAssertEqual(Set(Preferences.Key.allCases).subtracting(migrated),
                       [.automaticUpdateChecks, .navigationPreviewDelay])
        XCTAssertEqual(Preferences.Key.automaticUpdateChecks.rawValue, "SUEnableAutomaticChecks")
    }

    func testStoredValuesMoveToTheVersionedNames() {
        for sample in samples { defaults.set(sample.valid, forKey: sample.old) }

        PreferencesKeyMigration.migrate(defaults)

        for sample in samples {
            XCTAssertNil(defaults.object(forKey: sample.old), "\(sample.old) was not removed")
            XCTAssertEqual(stored(sample.key.rawValue) as? NSObject,
                           sample.valid as? NSObject, "\(sample.old) was not copied")
        }
        XCTAssertEqual(defaults.integer(forKey: PreferencesKeyMigration.schemaKey),
                       PreferencesKeyMigration.currentSchema)
    }

    func testMigratedChoicesLoadIntoPreferences() {
        for sample in samples { defaults.set(sample.valid, forKey: sample.old) }

        let preferences = Preferences(defaults: defaults)

        XCTAssertFalse(preferences.switcherEnabled)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertEqual(preferences.shortcut, .controlTab)
        XCTAssertNil(preferences.persistentShortcut, "an explicit unassigned choice survives")
        XCTAssertEqual(preferences.appearanceMode, .windowPreviews)
        XCTAssertEqual(preferences.expandedPreviewDelay, .fiveSeconds)
        XCTAssertEqual(preferences.switcherRevealDelay, .off)
        XCTAssertEqual(preferences.switcherDisplayPlacement, .specificDisplay)
        XCTAssertEqual(preferences.switcherDisplayID, "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        XCTAssertFalse(preferences.includeOtherSpaces)
        XCTAssertFalse(preferences.includeOtherDisplays)
        XCTAssertTrue(preferences.includeMinimizedWindows)
        XCTAssertTrue(preferences.includeHiddenApplicationWindows)
        XCTAssertTrue(preferences.includePictureInPictureWindows)
        XCTAssertTrue(preferences.showTabCounts)
        XCTAssertTrue(preferences.showMenuBarItem)
        XCTAssertTrue(preferences.showDockIcon)
        XCTAssertTrue(preferences.firstLaunchCompleted)
    }

    func testInvalidValuesAreDroppedAndFallBackToDefaults() {
        for sample in samples { defaults.set(sample.invalid, forKey: sample.old) }

        PreferencesKeyMigration.migrate(defaults)

        for sample in samples {
            XCTAssertNil(defaults.object(forKey: sample.old), "\(sample.old) was not removed")
            XCTAssertNil(stored(sample.key.rawValue), "invalid \(sample.old) was copied")
        }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.shortcut, Preferences.Defaults.shortcut)
        XCTAssertEqual(preferences.persistentShortcut, Preferences.Defaults.persistentShortcut)
        XCTAssertEqual(preferences.appearanceMode, Preferences.Defaults.appearanceMode)
        XCTAssertEqual(preferences.switcherEnabled, Preferences.Defaults.switcherEnabled)
        XCTAssertEqual(preferences.showDockIcon, Preferences.Defaults.showDockIcon)
        XCTAssertEqual(preferences.switcherDisplayID, Preferences.Defaults.switcherDisplayID)
    }

    func testAbsentValuesWriteOnlyTheSchema() {
        PreferencesKeyMigration.migrate(defaults)

        for sample in samples {
            XCTAssertNil(stored(sample.key.rawValue))
        }
        XCTAssertEqual(defaults.integer(forKey: PreferencesKeyMigration.schemaKey), 1)
    }

    func testASecondRunChangesNothing() {
        defaults.set(true, forKey: "showDockIcon")
        PreferencesKeyMigration.migrate(defaults)
        // an older build running afterwards writes the old name again
        defaults.set(false, forKey: "showDockIcon")

        PreferencesKeyMigration.migrate(defaults)

        XCTAssertEqual(stored(Preferences.Key.showDockIcon.rawValue) as? Bool, true)
        XCTAssertEqual(stored("showDockIcon") as? Bool, false)
    }

    func testSparklesKeyAndTheLegacyDelayKeepTheirNames() {
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        defaults.set("long", forKey: "navigationPreviewDelay")
        defaults.removeObject(forKey: "expandedPreviewDelay")

        let preferences = Preferences(defaults: defaults)

        XCTAssertFalse(preferences.automaticUpdateChecks)
        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, false)
        // the 1.1.2 migration still reads its unversioned name after the rename
        XCTAssertEqual(preferences.expandedPreviewDelay, .fiveSeconds)
        XCTAssertNil(defaults.object(forKey: "navigationPreviewDelay"))
    }

    func testRestoreDefaultsWorksOnTheVersionedNames() {
        for sample in samples { defaults.set(sample.valid, forKey: sample.old) }
        let preferences = Preferences(defaults: defaults)

        preferences.restoreDefaults()

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut, Preferences.Defaults.shortcut)
        XCTAssertEqual(reloaded.appearanceMode, Preferences.Defaults.appearanceMode)
        XCTAssertEqual(reloaded.showDockIcon, Preferences.Defaults.showDockIcon)
        XCTAssertEqual(reloaded.switcherDisplayID, Preferences.Defaults.switcherDisplayID)
        // mirrors a system registration and first-run state: never reset
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertTrue(reloaded.firstLaunchCompleted)
        for sample in samples {
            XCTAssertNil(defaults.object(forKey: sample.old))
        }
    }
}
