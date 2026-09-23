import Foundation
import Testing

@testable import WindowHopKit

/// The one-time move to versioned setting names (#111): every stored choice
/// survives, an invalid value falls back to its default, the old names are
/// removed, and a second run changes nothing.
@MainActor
final class PreferencesKeyMigrationTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() throws {
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// What this suite stores itself. `object(forKey:)` would also answer from
    /// the process-wide registration domain that any `Preferences` fills.
    private func stored(_ name: String) -> Any? {
        defaults.persistentDomain(forName: suiteName)?[name]
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
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
        (
            "switcherDisplayPlacement", .switcherDisplayPlacement,
            SwitcherDisplayPlacement.specificDisplay.rawValue, "everywhere"
        ),
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

    @Test func everyWindowHopOwnedKeyIsVersionedAndCoveredHere() {
        let migrated = Set(PreferencesKeyMigration.renamedKeys.map(\.new))
        #expect(migrated == Set(samples.map(\.key)))
        for (old, key) in PreferencesKeyMigration.renamedKeys {
            #expect(key.rawValue == "\(old).v1")
        }
        // the two names that keep their spelling, and why, are in the migration's doc
        #expect(
            Set(Preferences.Key.allCases).subtracting(migrated) == [.automaticUpdateChecks, .navigationPreviewDelay])
        #expect(Preferences.Key.automaticUpdateChecks.rawValue == "SUEnableAutomaticChecks")
    }

    @Test func storedValuesMoveToTheVersionedNames() {
        for sample in samples { defaults.set(sample.valid, forKey: sample.old) }

        PreferencesKeyMigration.migrate(defaults)

        for sample in samples {
            #expect(defaults.object(forKey: sample.old) == nil, "\(sample.old) was not removed")
            #expect(
                (stored(sample.key.rawValue) as? NSObject) == (sample.valid as? NSObject),
                "\(sample.old) was not copied")
        }
        #expect(
            defaults.integer(forKey: PreferencesKeyMigration.schemaKey) == PreferencesKeyMigration.currentSchema)
    }

    @Test func migratedChoicesLoadIntoPreferences() {
        for sample in samples { defaults.set(sample.valid, forKey: sample.old) }

        let preferences = Preferences(defaults: defaults)

        #expect(!preferences.switcherEnabled)
        #expect(preferences.launchAtLogin)
        #expect(preferences.shortcut == .controlTab)
        #expect(preferences.persistentShortcut == nil, "an explicit unassigned choice survives")
        #expect(preferences.appearanceMode == .windowPreviews)
        #expect(preferences.expandedPreviewDelay == .fiveSeconds)
        #expect(preferences.switcherRevealDelay == .off)
        #expect(preferences.switcherDisplayPlacement == .specificDisplay)
        #expect(preferences.switcherDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        #expect(!preferences.includeOtherSpaces)
        #expect(!preferences.includeOtherDisplays)
        #expect(preferences.includeMinimizedWindows)
        #expect(preferences.includeHiddenApplicationWindows)
        #expect(preferences.includePictureInPictureWindows)
        #expect(preferences.showTabCounts)
        #expect(preferences.showMenuBarItem)
        #expect(preferences.showDockIcon)
        #expect(preferences.firstLaunchCompleted)
    }

    @Test func invalidValuesAreDroppedAndFallBackToDefaults() {
        for sample in samples { defaults.set(sample.invalid, forKey: sample.old) }

        PreferencesKeyMigration.migrate(defaults)

        for sample in samples {
            #expect(defaults.object(forKey: sample.old) == nil, "\(sample.old) was not removed")
            #expect(stored(sample.key.rawValue) == nil, "invalid \(sample.old) was copied")
        }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.shortcut == Preferences.Defaults.shortcut)
        #expect(preferences.persistentShortcut == Preferences.Defaults.persistentShortcut)
        #expect(preferences.appearanceMode == Preferences.Defaults.appearanceMode)
        #expect(preferences.switcherEnabled == Preferences.Defaults.switcherEnabled)
        #expect(preferences.showDockIcon == Preferences.Defaults.showDockIcon)
        #expect(preferences.switcherDisplayID == Preferences.Defaults.switcherDisplayID)
    }

    @Test func absentValuesWriteOnlyTheSchema() {
        PreferencesKeyMigration.migrate(defaults)

        for sample in samples {
            #expect(stored(sample.key.rawValue) == nil)
        }
        #expect(defaults.integer(forKey: PreferencesKeyMigration.schemaKey) == 1)
    }

    @Test func aSecondRunChangesNothing() {
        defaults.set(true, forKey: "showDockIcon")
        PreferencesKeyMigration.migrate(defaults)
        // an older build running afterwards writes the old name again
        defaults.set(false, forKey: "showDockIcon")

        PreferencesKeyMigration.migrate(defaults)

        #expect((stored(Preferences.Key.showDockIcon.rawValue) as? Bool) == true)
        #expect((stored("showDockIcon") as? Bool) == false)
    }

    @Test func sparklesKeyAndTheLegacyDelayKeepTheirNames() {
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        defaults.set("long", forKey: "navigationPreviewDelay")
        defaults.removeObject(forKey: "expandedPreviewDelay")

        let preferences = Preferences(defaults: defaults)

        #expect(!preferences.automaticUpdateChecks)
        #expect((defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool) == false)
        // the 1.1.2 migration still reads its unversioned name after the rename
        #expect(preferences.expandedPreviewDelay == .fiveSeconds)
        #expect(defaults.object(forKey: "navigationPreviewDelay") == nil)
    }

    @Test func restoreDefaultsWorksOnTheVersionedNames() {
        for sample in samples { defaults.set(sample.valid, forKey: sample.old) }
        let preferences = Preferences(defaults: defaults)

        preferences.restoreDefaults()

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.shortcut == Preferences.Defaults.shortcut)
        #expect(reloaded.appearanceMode == Preferences.Defaults.appearanceMode)
        #expect(reloaded.showDockIcon == Preferences.Defaults.showDockIcon)
        #expect(reloaded.switcherDisplayID == Preferences.Defaults.switcherDisplayID)
        // mirrors a system registration and first-run state: never reset
        #expect(reloaded.launchAtLogin)
        #expect(reloaded.firstLaunchCompleted)
        for sample in samples {
            #expect(defaults.object(forKey: sample.old) == nil)
        }
    }
}
