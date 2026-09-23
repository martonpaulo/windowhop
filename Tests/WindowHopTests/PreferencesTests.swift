import Foundation
import Observation
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    @MainActor
    final class PreferencesTests {
        private var suiteName: String!
        private var defaults: UserDefaults!
        private var preferences: Preferences!
        /// Suites made by `unregisteredDefaults()`, removed with the test.
        private var unregisteredSuites: [(defaults: UserDefaults, name: String)] = []

        init() {
            suiteName = "windowhop-tests-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)
            preferences = Preferences(defaults: defaults)
        }

        isolated deinit {
            defaults.removePersistentDomain(forName: suiteName)
            for suite in unregisteredSuites { suite.defaults.removePersistentDomain(forName: suite.name) }
        }

        @Test func defaultValues() {
            #expect(preferences.switcherEnabled)
            #expect(!preferences.launchAtLogin)
            #expect(preferences.shortcut == .commandTab)
            #expect(preferences.persistentShortcut == .optionTab)
            #expect(preferences.appearanceMode == .appIcons)
            #expect(preferences.expandedPreviewDelay == .threeSeconds)
            #expect(preferences.expandedPreviewDelay.duration == 3)
            #expect(preferences.switcherRevealDelay == .milliseconds100)
            #expect(preferences.switcherDisplayPlacement == .allDisplays)
            #expect(preferences.switcherDisplayID == nil)
            #expect(preferences.includeOtherSpaces)
            #expect(preferences.includeOtherDisplays)
            #expect(!preferences.includeMinimizedWindows)
            #expect(!preferences.includeHiddenApplicationWindows)
            #expect(!preferences.includePictureInPictureWindows)
            #expect(!preferences.showTabCounts)
            #expect(!preferences.showMenuBarItem)
            #expect(!preferences.showDockIcon)
            #expect(preferences.automaticUpdateChecks)
            #expect(!preferences.firstLaunchCompleted)
        }

        @Test func roundTrip() {
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

            #expect(!restored.switcherEnabled)
            #expect(restored.launchAtLogin)
            #expect(restored.shortcut == .optionTab)
            #expect(restored.persistentShortcut == preferences.persistentShortcut)
            #expect(restored.appearanceMode == .windowPreviews)
            #expect(restored.expandedPreviewDelay == .fiveSeconds)
            #expect(restored.switcherRevealDelay == .milliseconds300)
            #expect(restored.switcherDisplayPlacement == .specificDisplay)
            #expect(restored.switcherDisplayID == "UUID-EXTERNAL")
            #expect(!restored.includeOtherSpaces)
            #expect(!restored.includeOtherDisplays)
            #expect(restored.includeMinimizedWindows)
            #expect(restored.includeHiddenApplicationWindows)
            #expect(restored.includePictureInPictureWindows)
            #expect(!restored.showTabCounts)
            #expect(restored.showMenuBarItem)
            #expect(restored.showDockIcon)
            #expect(!restored.automaticUpdateChecks)
            #expect(restored.firstLaunchCompleted)
        }

        @Test func loadsValuesPersistedByEarlierVersionsWithoutDataLoss() {
            let openShortcut = PersistentShortcut(
                keyCode: KeyCode.space, modifiers: [.maskAlternate])
            defaults.set(false, forKey: Preferences.Key.switcherEnabled.rawValue)
            defaults.set(
                ShortcutSpec.optionTab.rawValue,
                forKey: Preferences.Key.shortcut.rawValue)
            defaults.set(
                openShortcut.encoded,
                forKey: Preferences.Key.persistentShortcut.rawValue)
            defaults.set(
                AppearanceMode.windowPreviews.rawValue,
                forKey: Preferences.Key.appearanceMode.rawValue)
            defaults.set(false, forKey: Preferences.Key.showTabCounts.rawValue)
            defaults.set(true, forKey: Preferences.Key.showMenuBarItem.rawValue)

            let migrated = Preferences(defaults: defaults)

            #expect(!migrated.switcherEnabled)
            #expect(migrated.shortcut == .optionTab)
            #expect(migrated.persistentShortcut == openShortcut)
            #expect(migrated.appearanceMode == .windowPreviews)
            #expect(
                migrated.expandedPreviewDelay == .threeSeconds,
                "existing users inherit the documented three-second default")
            #expect(!migrated.includeMinimizedWindows)
            #expect(!migrated.includeHiddenApplicationWindows)
            #expect(!migrated.includePictureInPictureWindows)
            #expect(!migrated.showTabCounts)
            #expect(migrated.showMenuBarItem)
        }

        @Test func corruptShortcutFallsBackToCommandTab() {
            defaults.set("garbage", forKey: Preferences.Key.shortcut.rawValue)
            #expect(Preferences(defaults: defaults).shortcut == .commandTab)
        }

        @Test func corruptAppearanceAndBooleanValuesFallBackToDocumentedDefaults() {
            defaults.set("obsolete-mode", forKey: Preferences.Key.appearanceMode.rawValue)
            defaults.set("obsolete-delay", forKey: Preferences.Key.expandedPreviewDelay.rawValue)
            defaults.set("obsolete-delay", forKey: Preferences.Key.switcherRevealDelay.rawValue)
            defaults.set("not-a-boolean", forKey: Preferences.Key.includeOtherSpaces.rawValue)
            defaults.set(
                "not-a-boolean",
                forKey: Preferences.Key.includeMinimizedWindows.rawValue)
            defaults.set("not-a-boolean", forKey: Preferences.Key.showMenuBarItem.rawValue)

            let restored = Preferences(defaults: defaults)

            #expect(restored.appearanceMode == .appIcons)
            #expect(restored.expandedPreviewDelay == .threeSeconds)
            #expect(restored.switcherRevealDelay == .milliseconds100)
            #expect(restored.includeOtherSpaces)
            #expect(!restored.includeMinimizedWindows)
            #expect(!restored.showMenuBarItem)
        }

        @Test func corruptPersistentShortcutRestoresUnassignedDefault() {
            defaults.set("broken-shortcut", forKey: Preferences.Key.persistentShortcut.rawValue)
            #expect(Preferences(defaults: defaults).persistentShortcut == .optionTab)
        }

        @Test func expandedPreviewDelayPresetsAvoidRawMillisecondsInSettings() {
            #expect(ExpandedPreviewDelay.off.duration == nil)
            #expect(ExpandedPreviewDelay.oneSecond.duration == 1)
            #expect(ExpandedPreviewDelay.twoSeconds.duration == 2)
            #expect(ExpandedPreviewDelay.threeSeconds.duration == 3)
            #expect(ExpandedPreviewDelay.fiveSeconds.duration == 5)
            #expect(
                ExpandedPreviewDelay.allCases.map(\.displayName) == [
                    "Off", "1 second", "2 seconds", "3 seconds", "5 seconds",
                ])
        }

        @Test func onlyWindowPreviewsSupportsTheExpandedPreview() {
            #expect(!AppearanceMode.appIcons.supportsExpandedPreview)
            #expect(AppearanceMode.windowPreviews.supportsExpandedPreview)
        }

        @Test func changingTheAppearanceModeKeepsTheChosenExpandedPreviewDelay() {
            preferences.expandedPreviewDelay = .fiveSeconds
            preferences.appearanceMode = .windowPreviews
            preferences.appearanceMode = .appIcons
            preferences.appearanceMode = .windowPreviews
            #expect(Preferences(defaults: defaults).expandedPreviewDelay == .fiveSeconds)
        }

        /// Observation notifies once per assignment (at `willSet`, before the value
        /// changes), and an unrelated assignment does not notify at all. Each
        /// tracking call observes one change, so the test re-arms it.
        @Test func expandedPreviewDelayNotifiesObserversOncePerAssignment() {
            let changes = ChangeCounter()
            observeNextChange(changes) { _ = self.preferences.expandedPreviewDelay }
            preferences.switcherRevealDelay = .off
            #expect(changes.count == 0)

            preferences.expandedPreviewDelay = .oneSecond
            #expect(changes.count == 1)
            observeNextChange(changes) { _ = self.preferences.expandedPreviewDelay }
            preferences.expandedPreviewDelay = .fiveSeconds
            #expect(changes.count == 2)

            #expect(preferences.expandedPreviewDelay == .fiveSeconds)
            #expect(Preferences(defaults: defaults).expandedPreviewDelay == .fiveSeconds)
        }

        @Test func switcherRevealDelayNotifiesObserversOncePerAssignment() {
            let changes = ChangeCounter()
            observeNextChange(changes) { _ = self.preferences.switcherRevealDelay }

            preferences.switcherRevealDelay = .off
            #expect(changes.count == 1)
            observeNextChange(changes) { _ = self.preferences.switcherRevealDelay }
            preferences.switcherRevealDelay = .milliseconds500
            #expect(changes.count == 2)

            #expect(Preferences(defaults: defaults).switcherRevealDelay == .milliseconds500)
        }

        /// Settings binds every control through `@Bindable`, so every persisted
        /// property must be observable, not only the two above.
        @Test func everyConfigurablePreferenceIsObservable() {
            let changes = ChangeCounter()
            observeNextChange(changes) {
                _ = self.preferences.switcherEnabled
                _ = self.preferences.shortcut
                _ = self.preferences.persistentShortcut
                _ = self.preferences.appearanceMode
                _ = self.preferences.showTabCounts
                _ = self.preferences.includeOtherSpaces
                _ = self.preferences.showMenuBarItem
                _ = self.preferences.showDockIcon
                _ = self.preferences.automaticUpdateChecks
            }
            preferences.showDockIcon = true
            #expect(changes.count == 1)
        }

        @Test func legacyNavigationDelayMigratesToExpandedPreviewPreset() {
            defaults.removeObject(forKey: Preferences.Key.expandedPreviewDelay.rawValue)
            defaults.set("long", forKey: Preferences.Key.navigationPreviewDelay.rawValue)

            #expect(Preferences(defaults: defaults).expandedPreviewDelay == .fiveSeconds)
        }

        @Test func windowFilterChangesPublishRuntimeRefresh() async {
            await confirmation("window filters did change") { changed in
                // queue: nil delivers synchronously on the posting thread, this test's own
                let observer = NotificationCenter.default.addObserver(
                    forName: Preferences.windowFiltersDidChange,
                    object: preferences,
                    queue: nil
                ) { _ in changed() }
                defer { NotificationCenter.default.removeObserver(observer) }
                preferences.includePictureInPictureWindows = true
            }
        }

        @Test func explicitlyClearedPersistentShortcutSurvivesUpgrade() {
            defaults.set("", forKey: Preferences.Key.persistentShortcut.rawValue)
            #expect(Preferences(defaults: defaults).persistentShortcut == nil)
        }

        // MARK: - Launch at login default migration

        @Test func upgradedInstallKeepsOldLaunchAtLoginDefault() throws {
            let (upgradedDefaults, suite) = try unregisteredDefaults()
            upgradedDefaults.set(true, forKey: Preferences.Key.firstLaunchCompleted.rawValue)

            let upgraded = Preferences(defaults: upgradedDefaults)

            #expect(upgraded.launchAtLogin, "the installation accepted the old On default")
            #expect((stored(.launchAtLogin, in: suite) as? Bool) == true)
        }

        @Test func newInstallDefaultsLaunchAtLoginOff() throws {
            let (newDefaults, suite) = try unregisteredDefaults()

            let fresh = Preferences(defaults: newDefaults)

            #expect(!fresh.launchAtLogin)
            #expect(stored(.launchAtLogin, in: suite) == nil)
        }

        @Test func storedLaunchAtLoginChoiceSurvivesUpgrade() throws {
            for choice in [false, true] {
                let (upgradedDefaults, suite) = try unregisteredDefaults()
                upgradedDefaults.set(true, forKey: Preferences.Key.firstLaunchCompleted.rawValue)
                upgradedDefaults.set(choice, forKey: Preferences.Key.launchAtLogin.rawValue)

                let upgraded = Preferences(defaults: upgradedDefaults)

                #expect(upgraded.launchAtLogin == choice)
                #expect((stored(.launchAtLogin, in: suite) as? Bool) == choice)
            }
        }

        @Test func launchAtLoginMigrationIsIdempotent() throws {
            let (upgradedDefaults, suite) = try unregisteredDefaults()
            upgradedDefaults.set(true, forKey: Preferences.Key.firstLaunchCompleted.rawValue)
            _ = Preferences(defaults: upgradedDefaults)
            let migrated = UserDefaults.standard.persistentDomain(forName: suite) as NSDictionary?

            let again = Preferences(defaults: try #require(UserDefaults(suiteName: suite)))

            #expect(again.launchAtLogin)
            #expect(
                (UserDefaults.standard.persistentDomain(forName: suite) as NSDictionary?) == migrated)
        }

        // MARK: - Open WindowHop shortcut pair loaded against the switcher shortcut

        private var storedPersistentShortcut: Any? {
            defaults.persistentDomain(forName: suiteName)?[
                Preferences.Key.persistentShortcut.rawValue]
        }

        private func tapState(for loaded: Preferences) -> EventTapInterceptionState {
            EventTapInterceptionState(
                mode: .watching,
                holdModifier: loaded.shortcut.holdModifier,
                persistentShortcut: loaded.persistentShortcut)
        }

        /// A new suite in the state of a fresh app launch. The registration domain
        /// is process-wide, so defaults registered by earlier `Preferences` in this
        /// test process would answer for keys the suite never stored; the app has
        /// exactly one `Preferences`, whose migrations read before it registers.
        private func unregisteredDefaults() throws -> (UserDefaults, String) {
            let suite = "windowhop-tests-\(UUID().uuidString)"
            let clean = try #require(UserDefaults(suiteName: suite))
            unregisteredSuites.append((clean, suite))
            let registration = UserDefaults.registrationDomain
            var registered = clean.volatileDomain(forName: registration)
            for key in Preferences.defaultValues.keys { registered.removeValue(forKey: key) }
            clean.setVolatileDomain(registered, forName: registration)
            return (clean, suite)
        }

        private func stored(_ key: Preferences.Key, in suite: String) -> Any? {
            UserDefaults.standard.persistentDomain(forName: suite)?[key.rawValue]
        }

        @Test func legacyOptionTabSwitcherWithoutStoredOpenShortcutLoadsUnassigned() throws {
            let (legacy, suite) = try unregisteredDefaults()
            legacy.set(ShortcutSpec.optionTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)

            let loaded = Preferences(defaults: legacy)

            #expect(loaded.shortcut == .optionTab)
            #expect(loaded.persistentShortcut == nil)
            #expect((stored(.persistentShortcut, in: suite) as? String) == "")
            var state = tapState(for: loaded)
            #expect(
                state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
                    == EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
            // stable across launches, even after the switcher moves back to ⌘Tab
            loaded.shortcut = .commandTab
            #expect(Preferences(defaults: legacy).persistentShortcut == nil)
        }

        @Test func legacyCommandTabSwitcherStillReceivesOpenDefault() throws {
            let (legacy, suite) = try unregisteredDefaults()
            legacy.set(ShortcutSpec.commandTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)

            let loaded = Preferences(defaults: legacy)

            #expect(loaded.persistentShortcut == .optionTab)
            #expect(
                stored(.persistentShortcut, in: suite) == nil,
                "a compatible installation keeps following the registered default")
            var state = tapState(for: loaded)
            #expect(
                state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskAlternate)
                    == EventTapDecision(disposition: .consume, input: .openPersistent))
        }

        @Test func explicitlyClearedOpenShortcutStaysClearedWithAnySwitcher() {
            for spec in ShortcutSpec.allCases {
                defaults.set(spec.rawValue, forKey: Preferences.Key.shortcut.rawValue)
                defaults.set("", forKey: Preferences.Key.persistentShortcut.rawValue)

                let loaded = Preferences(defaults: defaults)

                #expect(loaded.persistentShortcut == nil, "\(spec)")
                #expect((storedPersistentShortcut as? String) == "", "\(spec)")
            }
        }

        @Test func validCustomPairIsPreserved() {
            let optionSpace = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskAlternate])
            defaults.set(ShortcutSpec.optionTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)
            defaults.set(optionSpace.encoded, forKey: Preferences.Key.persistentShortcut.rawValue)

            let loaded = Preferences(defaults: defaults)

            #expect(loaded.persistentShortcut == optionSpace)
            #expect((storedPersistentShortcut as? String) == optionSpace.encoded)
            var state = tapState(for: loaded)
            #expect(
                state.decide(type: .keyDown, keyCode: KeyCode.space, flags: .maskAlternate)
                    == EventTapDecision(disposition: .consume, input: .openPersistent))
        }

        @Test func storedConflictingOpenShortcutLoadsUnassigned() {
            let controlTab = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskControl])
            defaults.set(ShortcutSpec.controlTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)
            defaults.set(controlTab.encoded, forKey: Preferences.Key.persistentShortcut.rawValue)

            let loaded = Preferences(defaults: defaults)

            #expect(loaded.persistentShortcut == nil)
            #expect((storedPersistentShortcut as? String) == "")
            var state = tapState(for: loaded)
            #expect(
                state.decide(type: .keyDown, keyCode: KeyCode.tab, flags: .maskControl)
                    == EventTapDecision(disposition: .consume, input: .trigger(backward: false)))
        }

        @Test func corruptOpenShortcutWithConflictingSwitcherLoadsUnassigned() {
            defaults.set(ShortcutSpec.optionTab.rawValue, forKey: Preferences.Key.shortcut.rawValue)
            defaults.set("broken-shortcut", forKey: Preferences.Key.persistentShortcut.rawValue)

            let loaded = Preferences(defaults: defaults)

            #expect(loaded.persistentShortcut == nil)
            #expect((storedPersistentShortcut as? String) == "")
        }

        @Test func defaultPairIsValid() {
            // Restore Defaults assigns both keys in Set order, so the pair itself
            // must be valid for any intermediate state to settle correctly
            #expect(
                Preferences.Defaults.persistentShortcut?.validate(
                    against: Preferences.Defaults.shortcut) == nil)
        }

        @Test func restoreDefaultsResetsEveryConfigurablePreferenceAndPreservesInternalState() {
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

            #expect(preferences.switcherEnabled)
            #expect(
                preferences.launchAtLogin == !Preferences.Defaults.launchAtLogin,
                "launch at login mirrors a system registration; reset leaves it")
            #expect(
                (stored(.launchAtLogin, in: suiteName) as? Bool) == !Preferences.Defaults.launchAtLogin)
            #expect(preferences.shortcut == .commandTab)
            #expect(preferences.persistentShortcut == .optionTab)
            #expect(preferences.appearanceMode == .appIcons)
            #expect(preferences.expandedPreviewDelay == .threeSeconds)
            #expect(preferences.switcherRevealDelay == .milliseconds100)
            #expect(preferences.switcherDisplayPlacement == .allDisplays)
            #expect(preferences.switcherDisplayID == nil)
            #expect(preferences.includeOtherSpaces)
            #expect(preferences.includeOtherDisplays)
            #expect(!preferences.includeMinimizedWindows)
            #expect(!preferences.includeHiddenApplicationWindows)
            #expect(!preferences.includePictureInPictureWindows)
            #expect(!preferences.showTabCounts)
            #expect(!preferences.showMenuBarItem)
            #expect(!preferences.showDockIcon)
            #expect(preferences.automaticUpdateChecks)
            #expect(
                preferences.firstLaunchCompleted,
                "Restore Defaults must not repeat first-run state")
        }

        @Test func invalidStoredPlacementFallsBackToTheDocumentedDefault() {
            defaults.set(
                "mirrored-onto-the-ceiling",
                forKey: Preferences.Key.switcherDisplayPlacement.rawValue)

            let restored = Preferences(defaults: defaults)

            #expect(restored.switcherDisplayPlacement == .allDisplays)
        }

        @Test func anUpgradeWithoutAStoredPlacementReceivesTheNewDefault() throws {
            // an installation that predates the preference has nothing in its
            // persistent domain and must land on All displays with no migration step
            let suite = "windowhop-tests-\(UUID().uuidString)"
            let clean = try #require(UserDefaults(suiteName: suite))
            defer { clean.removePersistentDomain(forName: suite) }
            #expect(
                clean.persistentDomain(forName: suite)?[
                    Preferences.Key.switcherDisplayPlacement.rawValue] == nil)

            let restored = Preferences(defaults: clean)

            #expect(restored.switcherDisplayPlacement == .allDisplays)
            #expect(restored.switcherDisplayID == nil)
        }

        @Test func aChosenDisplaySurvivesBeingUnplugged() {
            // the id is the user's choice, not a cache of connected hardware: it is
            // kept verbatim so reconnecting the display restores the behavior
            preferences.switcherDisplayPlacement = .specificDisplay
            preferences.switcherDisplayID = "UUID-UNPLUGGED"

            let restored = Preferences(defaults: defaults)

            #expect(restored.switcherDisplayID == "UUID-UNPLUGGED")
        }

        @Test func clearingTheChosenDisplayPersistsAsNoChoice() {
            preferences.switcherDisplayID = "UUID-EXTERNAL"
            preferences.switcherDisplayID = nil

            #expect(Preferences(defaults: defaults).switcherDisplayID == nil)
        }

        @Test func everyNonInternalKeyParticipatesInRestoreDefaults() {
            let internalKeys: Set<Preferences.Key> = [
                .navigationPreviewDelay,
                .firstLaunchCompleted,
            ]
            // configurable, but a mirror of a macOS registration that reset must
            // not change; a future key still has to choose explicitly
            let systemMirroredKeys: Set<Preferences.Key> = [.launchAtLogin]
            #expect(
                Preferences.configurableKeys
                    == Set(Preferences.Key.allCases).subtracting(internalKeys)
                    .subtracting(systemMirroredKeys),
                "A new configurable preference must be considered by Restore Defaults")
        }

        @Test func restoreDefaultsPublishesOneCoherentWindowFilterRefresh() {
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
                queue: nil
            ) { _ in refreshCount += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }

            preferences.restoreDefaults()

            #expect(refreshCount == 1)
        }
    }
}

/// Counts Observation `onChange` calls. They arrive synchronously on the main
/// thread that assigns the property, so the unchecked conformance is safe here.
private final class ChangeCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor
private func observeNextChange(_ changes: ChangeCounter, _ read: () -> Void) {
    withObservationTracking(read, onChange: { changes.increment() })
}
