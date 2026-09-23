import XCTest

@testable import WindowHopKit

/// The one-time copy from the old bundle identifier's defaults domain (#43).
/// Every test works on an isolated suite and a legacy domain given as a
/// dictionary: the real old and new domains are never read or written here.
@MainActor
final class LegacyDomainMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
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

    func testAReleasedDomainIsCopiedAndThenMovedToVersionedNames() {
        migrate(releasedDomain)
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.shortcut, .controlTab)
        XCTAssertEqual(preferences.appearanceMode, .windowPreviews)
        XCTAssertTrue(preferences.showDockIcon)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertFalse(preferences.automaticUpdateChecks)
        XCTAssertTrue(preferences.firstLaunchCompleted)
        // #111's migration ran on the copied names
        XCTAssertNil(currentDomain["shortcut"])
        XCTAssertEqual(currentDomain["shortcut.v1"] as? String, ShortcutSpec.controlTab.rawValue)
        XCTAssertEqual(currentDomain[PreferencesKeyMigration.schemaKey] as? Int, 1)
        XCTAssertEqual(currentDomain[LegacyDomainMigration.markerKey] as? Bool, true)
    }

    func testAVersionedDomainIsCopiedAsItIs() {
        migrate([
            "shortcut.v1": ShortcutSpec.controlTab.rawValue,
            "showTabCounts.v1": true,
            PreferencesKeyMigration.schemaKey: 1,
        ])
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.shortcut, .controlTab)
        XCTAssertTrue(preferences.showTabCounts)
    }

    func testThe112DwellPresetStillMigratesAfterTheCopy() {
        migrate(["navigationPreviewDelay": "long"])
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.expandedPreviewDelay, .fiveSeconds)
        XCTAssertNil(currentDomain["navigationPreviewDelay"])
    }

    func testUnknownNamesAreIgnored() {
        migrate([
            "showDockIcon": true, "SULastCheckTime": Date(), "NSWindow Frame Other": "0 0 1 1",
            "unrelated": 1,
        ])

        XCTAssertEqual(
            Set(currentDomain.keys), ["showDockIcon", LegacyDomainMigration.markerKey])
    }

    func testCallerNamesAreCopied() {
        let frame = "NSWindow Frame WindowHopSettings"
        migrate([frame: "10 20 600 400 0 0 1512 944 "], extraNames: [frame])

        XCTAssertEqual(currentDomain[frame] as? String, "10 20 600 400 0 0 1512 944 ")
    }

    func testValuesAlreadyInTheNewDomainWin() {
        defaults.set(false, forKey: "showDockIcon")
        migrate(releasedDomain)

        XCTAssertEqual(currentDomain["showDockIcon"] as? Bool, false)
        XCTAssertEqual(currentDomain["launchAtLogin"] as? Bool, true)
    }

    func testASecondLaunchCopiesNothing() {
        migrate(releasedDomain)
        let preferences = Preferences(defaults: defaults)
        preferences.showDockIcon = false

        // an older build changes its own domain afterwards
        migrate(["showDockIcon": true, "showTabCounts": true])

        XCTAssertEqual(currentDomain["showDockIcon.v1"] as? Bool, false)
        XCTAssertNil(currentDomain["showTabCounts"])
        XCTAssertNil(
            LegacyDomainMigration.valuesToCopy(
                legacyDomain: releasedDomain, currentDomain: currentDomain))
    }

    func testAnAbsentLegacyDomainWritesOnlyTheMarker() {
        migrate(nil)

        XCTAssertEqual(Set(currentDomain.keys), [LegacyDomainMigration.markerKey])
    }

    func testTheMarkerIsNotASetting() {
        XCTAssertFalse(
            Preferences.configurableKeys.map(\.rawValue).contains(LegacyDomainMigration.markerKey))
        XCTAssertNil(Preferences.Key(rawValue: LegacyDomainMigration.markerKey))
    }
}
