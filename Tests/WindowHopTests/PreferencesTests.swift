import XCTest
import Combine
@testable import WindowHopCore

@MainActor
final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = Preferences(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testDefaults() {
        XCTAssertTrue(preferences.switcherEnabled)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertEqual(preferences.shortcut, .commandTab)
        XCTAssertEqual(preferences.persistentShortcut, .optionTab)
        XCTAssertEqual(preferences.appearanceMode, .appIcons)
        XCTAssertEqual(preferences.expandedPreviewDelay, .threeSeconds)
        XCTAssertEqual(preferences.expandedPreviewDelay.duration, 3)
        XCTAssertEqual(preferences.switcherRevealDelay, .milliseconds100)
        XCTAssertEqual(preferences.switcherDisplayPlacement, .allDisplays)
        XCTAssertNil(preferences.switcherDisplayID)
        XCTAssertTrue(preferences.includeOtherSpaces)
        XCTAssertTrue(preferences.includeOtherDisplays)
        XCTAssertFalse(preferences.includeMinimizedWindows)
        XCTAssertFalse(preferences.includeHiddenApplicationWindows)
        XCTAssertFalse(preferences.includePictureInPictureWindows)
        XCTAssertFalse(preferences.showTabCounts)
        XCTAssertFalse(preferences.showMenuBarItem)
        XCTAssertFalse(preferences.showDockIcon)
        XCTAssertTrue(preferences.automaticUpdateChecks)
        XCTAssertFalse(preferences.firstLaunchCompleted)
    }

    func testRoundTrip() {
        preferences.switcherEnabled = false
        preferences.launchAtLogin = true
        preferences.shortcut = .optionTab
        preferences.persistentShortcut = PersistentShortcut(
            keyCode: KeyCode.space, modifiers: [.maskAlternate])
        preferences.appearanceMode = .windowPreviews
        preferences.expandedPreviewDelay = .fiveSeconds
        preferences.switcherRevealDelay = .milliseconds300
        preferences.switcherDisplayPlacement = .specificDisplay
        preferences.switcherDisplayID = "UUID-EXTERNAL"
        preferences.includeOtherSpaces = false
        preferences.includeOtherDisplays = false
        preferences.includeMinimizedWindows = true
        preferences.includeHiddenApplicationWindows = true
        preferences.includePictureInPictureWindows = true
        preferences.showTabCounts = false
        preferences.showMenuBarItem = true
        preferences.showDockIcon = true
        preferences.automaticUpdateChecks = false
        preferences.firstLaunchCompleted = true

        let restored = Preferences(defaults: defaults)

        XCTAssertFalse(restored.switcherEnabled)
        XCTAssertTrue(restored.launchAtLogin)
        XCTAssertEqual(restored.shortcut, .optionTab)
        XCTAssertEqual(restored.persistentShortcut, preferences.persistentShortcut)
        XCTAssertEqual(restored.appearanceMode, .windowPreviews)
        XCTAssertEqual(restored.expandedPreviewDelay, .fiveSeconds)
        XCTAssertEqual(restored.switcherRevealDelay, .milliseconds300)
        XCTAssertEqual(restored.switcherDisplayPlacement, .specificDisplay)
        XCTAssertEqual(restored.switcherDisplayID, "UUID-EXTERNAL")
        XCTAssertFalse(restored.includeOtherSpaces)
        XCTAssertFalse(restored.includeOtherDisplays)
        XCTAssertTrue(restored.includeMinimizedWindows)
        XCTAssertTrue(restored.includeHiddenApplicationWindows)
        XCTAssertTrue(restored.includePictureInPictureWindows)
        XCTAssertFalse(restored.showTabCounts)
        XCTAssertTrue(restored.showMenuBarItem)
        XCTAssertTrue(restored.showDockIcon)
        XCTAssertFalse(restored.automaticUpdateChecks)
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
        defaults.set("obsolete-delay", forKey: Preferences.Key.switcherRevealDelay.rawValue)
        defaults.set("not-a-boolean", forKey: Preferences.Key.includeOtherSpaces.rawValue)
        defaults.set("not-a-boolean",
                     forKey: Preferences.Key.includeMinimizedWindows.rawValue)
        defaults.set("not-a-boolean", forKey: Preferences.Key.showMenuBarItem.rawValue)

        let restored = Preferences(defaults: defaults)

        XCTAssertEqual(restored.appearanceMode, .appIcons)
        XCTAssertEqual(restored.expandedPreviewDelay, .threeSeconds)
        XCTAssertEqual(restored.switcherRevealDelay, .milliseconds100)
        XCTAssertTrue(restored.includeOtherSpaces)
        XCTAssertFalse(restored.includeMinimizedWindows)
        XCTAssertFalse(restored.showMenuBarItem)
    }

    func testCorruptPersistentShortcutRestoresUnassignedDefault() {
        defaults.set("broken-shortcut", forKey: Preferences.Key.persistentShortcut.rawValue)
        XCTAssertEqual(Preferences(defaults: defaults).persistentShortcut, .optionTab)
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

    func testOnlyWindowPreviewsSupportsTheExpandedPreview() {
        XCTAssertFalse(AppearanceMode.appIcons.supportsExpandedPreview)
        XCTAssertTrue(AppearanceMode.windowPreviews.supportsExpandedPreview)
    }

    func testChangingTheAppearanceModeKeepsTheChosenExpandedPreviewDelay() {
        preferences.expandedPreviewDelay = .fiveSeconds
        preferences.appearanceMode = .windowPreviews
        preferences.appearanceMode = .appIcons
        preferences.appearanceMode = .windowPreviews
        XCTAssertEqual(Preferences(defaults: defaults).expandedPreviewDelay, .fiveSeconds)
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

    func testSwitcherRevealDelayPublishesRuntimeUpdatesImmediately() {
        var observed: [SwitcherRevealDelay] = []
        let observation = preferences.$switcherRevealDelay.sink {
            observed.append($0)
        }

        preferences.switcherRevealDelay = .off

        XCTAssertEqual(observed, [.milliseconds100, .off])
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

    func testExplicitlyClearedPersistentShortcutSurvivesUpgrade() {
        defaults.set("", forKey: Preferences.Key.persistentShortcut.rawValue)
        XCTAssertNil(Preferences(defaults: defaults).persistentShortcut)
    }

    // MARK: - Launch at login default migration

    func testUpgradedInstallKeepsOldLaunchAtLoginDefault() {
        let (upgradedDefaults, suite) = unregisteredDefaults()
        upgradedDefaults.set(true, forKey: Preferences.Key.firstLaunchCompleted.rawValue)

        let upgraded = Preferences(defaults: upgradedDefaults)

        XCTAssertTrue(upgraded.launchAtLogin, "the installation accepted the old On default")
        XCTAssertEqual(stored(.launchAtLogin, in: suite) as? Bool, true)
    }

    func testNewInstallDefaultsLaunchAtLoginOff() {
        let (newDefaults, suite) = unregisteredDefaults()

        let fresh = Preferences(defaults: newDefaults)

        XCTAssertFalse(fresh.launchAtLogin)
        XCTAssertNil(stored(.launchAtLogin, in: suite))
    }

    func testStoredLaunchAtLoginChoiceSurvivesUpgrade() {
        for choice in [false, true] {
            let (upgradedDefaults, suite) = unregisteredDefaults()
            upgradedDefaults.set(true, forKey: Preferences.Key.firstLaunchCompleted.rawValue)
            upgradedDefaults.set(choice, forKey: Preferences.Key.launchAtLogin.rawValue)

            let upgraded = Preferences(defaults: upgradedDefaults)

            XCTAssertEqual(upgraded.launchAtLogin, choice)
            XCTAssertEqual(stored(.launchAtLogin, in: suite) as? Bool, choice)
        }
    }

    func testLaunchAtLoginMigrationIsIdempotent() {
        let (upgradedDefaults, suite) = unregisteredDefaults()
        upgradedDefaults.set(true, forKey: Preferences.Key.firstLaunchCompleted.rawValue)
        _ = Preferences(defaults: upgradedDefaults)
        let migrated = UserDefaults.standard.persistentDomain(forName: suite) as NSDictionary?

        let again = Preferences(defaults: UserDefaults(suiteName: suite)!)

        XCTAssertTrue(again.launchAtLogin)
        XCTAssertEqual(UserDefaults.standard.persistentDomain(forName: suite) as NSDictionary?,
                       migrated)
    }

    // MARK: - Open WindowHop shortcut pair loaded against the switcher shortcut

    private var storedPersistentShortcut: Any? {
        defaults.persistentDomain(forName: suiteName)?[
            Preferences.Key.persistentShortcut.rawValue]
    }

    private func tapState(for loaded: Preferences) -> EventTapInterceptionState {
        EventTapInterceptionState(mode: .watching,
                                  holdModifier: loaded.shortcut.holdModifier,
                                  persistentShortcut: loaded.persistentShortcut)
    }

    /// A new suite in the state of a fresh app launch. The registration domain
    /// is process-wide, so defaults registered by earlier `Preferences` in this
    /// test process would answer for keys the suite never stored; the app has
    /// exactly one `Preferences`, whose migrations read before it registers.
    private func unregisteredDefaults() -> (UserDefaults, String) {
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let clean = UserDefaults(suiteName: suite)!
        addTeardownBlock { clean.removePersistentDomain(forName: suite) }
        let registration = UserDefaults.registrationDomain
        var registered = clean.volatileDomain(forName: registration)
        for key in Preferences.defaultValues.keys { registered.removeValue(forKey: key) }
        clean.setVolatileDomain(registered, forName: registration)
        return (clean, suite)
    }

    private func stored(_ key: Preferences.Key, in suite: String) -> Any? {
        UserDefaults.standard.persistentDomain(forName: suite)?[key.rawValue]
    }

    func testLegacyOptionTabSwitcherWithoutStoredOpenShortcutLoadsUnassigned() {
        let (legacy, suite) = unregisteredDefaults()
        legacy.set(ShortcutSpec.optionTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)

        let loaded = Preferences(defaults: legacy)

        XCTAssertEqual(loaded.shortcut, .optionTab)
        XCTAssertNil(loaded.persistentShortcut)
        XCTAssertEqual(stored(.persistentShortcut, in: suite) as? String, "")
        var state = tapState(for: loaded)
        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate),
            EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
        // stable across launches, even after the switcher moves back to ⌘Tab
        loaded.shortcut = .commandTab
        XCTAssertNil(Preferences(defaults: legacy).persistentShortcut)
    }

    func testLegacyCommandTabSwitcherStillReceivesOpenDefault() {
        let (legacy, suite) = unregisteredDefaults()
        legacy.set(ShortcutSpec.commandTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)

        let loaded = Preferences(defaults: legacy)

        XCTAssertEqual(loaded.persistentShortcut, .optionTab)
        XCTAssertNil(stored(.persistentShortcut, in: suite),
                     "a compatible installation keeps following the registered default")
        var state = tapState(for: loaded)
        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate),
            EventTapDecision(disposition: .consume, input: .openPersistent))
    }

    func testExplicitlyClearedOpenShortcutStaysClearedWithAnySwitcher() {
        for spec in ShortcutSpec.allCases {
            defaults.set(spec.rawValue, forKey: Preferences.Key.shortcut.rawValue)
            defaults.set("", forKey: Preferences.Key.persistentShortcut.rawValue)

            let loaded = Preferences(defaults: defaults)

            XCTAssertNil(loaded.persistentShortcut, "\(spec)")
            XCTAssertEqual(storedPersistentShortcut as? String, "", "\(spec)")
        }
    }

    func testValidCustomPairIsPreserved() {
        let optionSpace = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate])
        defaults.set(ShortcutSpec.optionTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)
        defaults.set(optionSpace.encoded, forKey: Preferences.Key.persistentShortcut.rawValue)

        let loaded = Preferences(defaults: defaults)

        XCTAssertEqual(loaded.persistentShortcut, optionSpace)
        XCTAssertEqual(storedPersistentShortcut as? String, optionSpace.encoded)
        var state = tapState(for: loaded)
        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.space, flags: .maskAlternate),
            EventTapDecision(disposition: .consume, input: .openPersistent))
    }

    func testStoredConflictingOpenShortcutLoadsUnassigned() {
        let controlTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskControl])
        defaults.set(ShortcutSpec.controlTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)
        defaults.set(controlTab.encoded, forKey: Preferences.Key.persistentShortcut.rawValue)

        let loaded = Preferences(defaults: defaults)

        XCTAssertNil(loaded.persistentShortcut)
        XCTAssertEqual(storedPersistentShortcut as? String, "")
        var state = tapState(for: loaded)
        XCTAssertEqual(
            state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskControl),
            EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
    }

    func testCorruptOpenShortcutWithConflictingSwitcherLoadsUnassigned() {
        defaults.set(ShortcutSpec.optionTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)
        defaults.set("broken-shortcut", forKey: Preferences.Key.persistentShortcut.rawValue)

        let loaded = Preferences(defaults: defaults)

        XCTAssertNil(loaded.persistentShortcut)
        XCTAssertEqual(storedPersistentShortcut as? String, "")
    }

    func testDefaultPairIsValid() {
        // Restore Defaults assigns both keys in Set order, so the pair itself
        // must be valid for any intermediate state to settle correctly
        XCTAssertNil(Preferences.Defaults.persistentShortcut?.validate(
            against: Preferences.Defaults.shortcut))
    }

    func testRestoreDefaultsResetsEveryConfigurablePreferenceAndPreservesInternalState() {
        preferences.switcherEnabled = false
        preferences.launchAtLogin = !Preferences.Defaults.launchAtLogin
        preferences.shortcut = .controlTab
        preferences.persistentShortcut = nil
        preferences.appearanceMode = .windowPreviews
        preferences.expandedPreviewDelay = .off
        preferences.switcherRevealDelay = .off
        preferences.includeOtherSpaces = false
        preferences.includeOtherDisplays = false
        preferences.includeMinimizedWindows = true
        preferences.includeHiddenApplicationWindows = true
        preferences.includePictureInPictureWindows = true
        preferences.showTabCounts = true
        preferences.showMenuBarItem = true
        preferences.showDockIcon = true
        preferences.automaticUpdateChecks = false
        preferences.firstLaunchCompleted = true

        preferences.restoreDefaults()

        XCTAssertTrue(preferences.switcherEnabled)
        XCTAssertEqual(preferences.launchAtLogin, !Preferences.Defaults.launchAtLogin,
                       "launch at login mirrors a system registration; reset leaves it")
        XCTAssertEqual(stored(.launchAtLogin, in: suiteName) as? Bool,
                       !Preferences.Defaults.launchAtLogin)
        XCTAssertEqual(preferences.shortcut, .commandTab)
        XCTAssertEqual(preferences.persistentShortcut, .optionTab)
        XCTAssertEqual(preferences.appearanceMode, .appIcons)
        XCTAssertEqual(preferences.expandedPreviewDelay, .threeSeconds)
        XCTAssertEqual(preferences.switcherRevealDelay, .milliseconds100)
        XCTAssertEqual(preferences.switcherDisplayPlacement, .allDisplays)
        XCTAssertNil(preferences.switcherDisplayID)
        XCTAssertTrue(preferences.includeOtherSpaces)
        XCTAssertTrue(preferences.includeOtherDisplays)
        XCTAssertFalse(preferences.includeMinimizedWindows)
        XCTAssertFalse(preferences.includeHiddenApplicationWindows)
        XCTAssertFalse(preferences.includePictureInPictureWindows)
        XCTAssertFalse(preferences.showTabCounts)
        XCTAssertFalse(preferences.showMenuBarItem)
        XCTAssertFalse(preferences.showDockIcon)
        XCTAssertTrue(preferences.automaticUpdateChecks)
        XCTAssertTrue(preferences.firstLaunchCompleted,
                      "Restore Defaults must not repeat first-run state")
    }

    func testInvalidStoredPlacementFallsBackToTheDocumentedDefault() {
        defaults.set("mirrored-onto-the-ceiling",
                     forKey: Preferences.Key.switcherDisplayPlacement.rawValue)

        let restored = Preferences(defaults: defaults)

        XCTAssertEqual(restored.switcherDisplayPlacement, .allDisplays)
    }

    func testAnUpgradeWithoutAStoredPlacementReceivesTheNewDefault() {
        // an installation that predates the preference has nothing in its
        // persistent domain and must land on All displays with no migration step
        let suite = "windowhop-tests-\(UUID().uuidString)"
        let clean = UserDefaults(suiteName: suite)!
        defer { clean.removePersistentDomain(forName: suite) }
        XCTAssertNil(clean.persistentDomain(forName: suite)?[
            Preferences.Key.switcherDisplayPlacement.rawValue])

        let restored = Preferences(defaults: clean)

        XCTAssertEqual(restored.switcherDisplayPlacement, .allDisplays)
        XCTAssertNil(restored.switcherDisplayID)
    }

    func testAChosenDisplaySurvivesBeingUnplugged() {
        // the id is the user's choice, not a cache of connected hardware: it is
        // kept verbatim so reconnecting the display restores the behavior
        preferences.switcherDisplayPlacement = .specificDisplay
        preferences.switcherDisplayID = "UUID-UNPLUGGED"

        let restored = Preferences(defaults: defaults)

        XCTAssertEqual(restored.switcherDisplayID, "UUID-UNPLUGGED")
    }

    func testClearingTheChosenDisplayPersistsAsNoChoice() {
        preferences.switcherDisplayID = "UUID-EXTERNAL"
        preferences.switcherDisplayID = nil

        XCTAssertNil(Preferences(defaults: defaults).switcherDisplayID)
    }

    func testEveryNonInternalKeyParticipatesInRestoreDefaults() {
        let internalKeys: Set<Preferences.Key> = [
            .navigationPreviewDelay,
            .firstLaunchCompleted,
        ]
        // configurable, but a mirror of a macOS registration that reset must
        // not change; a future key still has to choose explicitly
        let systemMirroredKeys: Set<Preferences.Key> = [.launchAtLogin]
        XCTAssertEqual(
            Preferences.configurableKeys,
            Set(Preferences.Key.allCases).subtracting(internalKeys)
                .subtracting(systemMirroredKeys),
            "A new configurable preference must be considered by Restore Defaults")
    }

    func testRestoreDefaultsPublishesOneCoherentWindowFilterRefresh() {
        preferences.includeOtherSpaces = false
        preferences.includeOtherDisplays = false
        preferences.includeMinimizedWindows = true
        preferences.includeHiddenApplicationWindows = true
        preferences.includePictureInPictureWindows = true
        // queue: nil delivers synchronously on the posting thread, this test's own
        nonisolated(unsafe) var refreshCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: Preferences.windowFiltersDidChange,
            object: preferences,
            queue: nil) { _ in refreshCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        preferences.restoreDefaults()

        XCTAssertEqual(refreshCount, 1)
    }
}
