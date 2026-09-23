import Foundation
import Testing

@testable import WindowHopKit

/// The one-time copy from the old bundle identifier's defaults domain (#43).
/// Every test works on an isolated suite and a legacy domain given as a
/// dictionary: the real old and new domains are never read or written here.
@MainActor
final class LegacyDomainMigrationTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() throws {
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// What the suite stores itself, without the process-wide registration domain.
    private var currentDomain: [String: Any] {
        defaults.persistentDomain(forName: suiteName) ?? [:]
    }

    private func migrate(_ legacy: [String: Any]?, extraNames: Set<String> = []) {
        LegacyDomainMigration.migrate(
            defaults, currentDomain: currentDomain, legacyDomain: legacy, extraNames: extraNames)
    }

    /// A 2.0.0 domain: unversioned names, no schema.
    private let releasedDomain: [String: Any] = [
        "shortcut": ShortcutSpec.controlTab.rawValue,
        "appearanceMode": AppearanceMode.windowPreviews.rawValue,
        "showDockIcon": true,
        "launchAtLogin": true,
        "SUEnableAutomaticChecks": false,
        "firstLaunchCompleted": true,
    ]

    @Test func aReleasedDomainIsCopiedAndThenMovedToVersionedNames() {
        migrate(releasedDomain)
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.shortcut == .controlTab)
        #expect(preferences.appearanceMode == .windowPreviews)
        #expect(preferences.showDockIcon)
        #expect(preferences.launchAtLogin)
        #expect(!preferences.automaticUpdateChecks)
        #expect(preferences.firstLaunchCompleted)
        // #111's migration ran on the copied names
        #expect(currentDomain["shortcut"] == nil)
        #expect((currentDomain["shortcut.v1"] as? String) == ShortcutSpec.controlTab.rawValue)
        #expect((currentDomain[PreferencesKeyMigration.schemaKey] as? Int) == 1)
        #expect((currentDomain[LegacyDomainMigration.markerKey] as? Bool) == true)
    }

    @Test func aVersionedDomainIsCopiedAsItIs() {
        migrate([
            "shortcut.v1": ShortcutSpec.controlTab.rawValue,
            "showTabCounts.v1": true,
            PreferencesKeyMigration.schemaKey: 1,
        ])
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.shortcut == .controlTab)
        #expect(preferences.showTabCounts)
    }

    @Test func the112DwellPresetStillMigratesAfterTheCopy() {
        migrate(["navigationPreviewDelay": "long"])
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.expandedPreviewDelay == .fiveSeconds)
        #expect(currentDomain["navigationPreviewDelay"] == nil)
    }

    @Test func unknownNamesAreIgnored() {
        migrate([
            "showDockIcon": true, "SULastCheckTime": Date(), "NSWindow Frame Other": "0 0 1 1",
            "unrelated": 1,
        ])

        #expect(
            Set(currentDomain.keys) == ["showDockIcon", LegacyDomainMigration.markerKey])
    }

    @Test func callerNamesAreCopied() {
        let frame = "NSWindow Frame WindowHopSettings"
        migrate([frame: "10 20 600 400 0 0 1512 944 "], extraNames: [frame])

        #expect((currentDomain[frame] as? String) == "10 20 600 400 0 0 1512 944 ")
    }

    @Test func valuesAlreadyInTheNewDomainWin() {
        defaults.set(false, forKey: "showDockIcon")
        migrate(releasedDomain)

        #expect((currentDomain["showDockIcon"] as? Bool) == false)
        #expect((currentDomain["launchAtLogin"] as? Bool) == true)
    }

    @Test func aSecondLaunchCopiesNothing() {
        migrate(releasedDomain)
        let preferences = Preferences(defaults: defaults)
        preferences.showDockIcon = false

        // an older build changes its own domain afterwards
        migrate(["showDockIcon": true, "showTabCounts": true])

        #expect((currentDomain["showDockIcon.v1"] as? Bool) == false)
        #expect(currentDomain["showTabCounts"] == nil)
        #expect(
            LegacyDomainMigration.valuesToCopy(
                legacyDomain: releasedDomain, currentDomain: currentDomain) == nil)
    }

    @Test func anAbsentLegacyDomainWritesOnlyTheMarker() {
        migrate(nil)

        #expect(Set(currentDomain.keys) == [LegacyDomainMigration.markerKey])
    }

    @Test func theMarkerIsNotASetting() {
        #expect(
            !Preferences.configurableKeys.map(\.rawValue).contains(LegacyDomainMigration.markerKey))
        #expect(Preferences.Key(rawValue: LegacyDomainMigration.markerKey) == nil)
    }
}
