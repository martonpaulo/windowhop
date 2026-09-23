import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// The menu bar item's menu, exercised without creating an `NSStatusItem`:
    /// its contents must not depend on whether the updater started before or
    /// after the menu was built, and refreshing it must never duplicate items.
    @MainActor
    final class StatusItemMenuTests {
        private var suiteName: String!
        private var defaults: UserDefaults!
        private var preferences: Preferences!
        private var accessibilityGranted = true
        private var updaterAvailable = false
        private var canCheck = false
        private var controller: StatusItemController!

        init() {
            suiteName = "windowhop-tests-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)
            preferences = Preferences(defaults: defaults)
            accessibilityGranted = true
            updaterAvailable = false
            canCheck = false
            controller = StatusItemController(
                preferences: preferences,
                accessibilityGranted: { [unowned self] in self.accessibilityGranted },
                updaterAvailable: { [unowned self] in self.updaterAvailable },
                canCheckForUpdates: { [unowned self] in self.canCheck },
                actions: StatusItemController.Actions(
                    openAccessibilitySetup: {},
                    openSettings: {},
                    checkForUpdates: {}))
        }

        isolated deinit {
            controller = nil
            defaults.removePersistentDomain(forName: suiteName)
        }

        private func updateItem(in menu: NSMenu) -> NSMenuItem? {
            menu.items.first { $0.title == "Check for Updates…" }
        }

        @Test func updateCommandAppearsWhenUpdaterStartsAfterMenuWasBuilt() throws {
            let menu = controller.makeMenu()
            controller.refresh(menu)
            #expect(updateItem(in: menu)?.isHidden == true)

            updaterAvailable = true
            canCheck = true
            // what AppKit does when the menu opens
            menu.delegate?.menuNeedsUpdate?(menu)

            let item = try #require(updateItem(in: menu))
            #expect(!item.isHidden)
            #expect(controller.validateMenuItem(item))
        }

        @Test func updateCommandHiddenWithoutUpdater() {
            let menu = controller.makeMenu()
            controller.refresh(menu)
            #expect(updateItem(in: menu)?.isHidden == true)
        }

        @Test func updateCommandDisabledWhileSparkleCannotCheck() throws {
            updaterAvailable = true
            canCheck = false
            let menu = controller.makeMenu()
            controller.refresh(menu)
            let item = try #require(updateItem(in: menu))
            #expect(!item.isHidden)
            #expect(!controller.validateMenuItem(item))
        }

        @Test func repeatedRefreshNeverDuplicatesItems() {
            updaterAvailable = true
            let menu = controller.makeMenu()
            let countBefore = menu.items.count
            for _ in 0..<3 { controller.refresh(menu) }
            #expect(menu.items.count == countBefore)
            #expect(menu.items.filter { $0.title == "Check for Updates…" }.count == 1)
            #expect(menu.items.filter { ["Enable", "Disable"].contains($0.title) }.count == 1)
        }

        @Test func toggleTitleFollowsSwitcherEnabled() {
            let menu = controller.makeMenu()
            preferences.switcherEnabled = false
            controller.refresh(menu)
            #expect(menu.items.contains { $0.title == "Enable" })
            preferences.switcherEnabled = true
            controller.refresh(menu)
            #expect(menu.items.contains { $0.title == "Disable" })
        }

        // MARK: - State presentation (#63)

        private func visibleTitles(_ menu: NSMenu) -> [String] {
            menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
        }

        @Test func activeStateShowsNoStatusRow() {
            let menu = controller.makeMenu()
            controller.refresh(menu)
            #expect(visibleTitles(menu) == ["Disable", "Settings…", "Quit WindowHop"])
            #expect(menu.items.first { !$0.isHidden }?.isSeparatorItem == false)
        }

        @Test func pausedStateShowsDisabledStatusRowFirst() throws {
            preferences.switcherEnabled = false
            let menu = controller.makeMenu()
            controller.refresh(menu)
            #expect(visibleTitles(menu) == ["Paused", "Enable", "Settings…", "Quit WindowHop"])
            let statusRow = try #require(menu.items.first { $0.title == "Paused" })
            #expect(statusRow.action == nil)
            #expect(!visibleTitles(menu).contains("Open Accessibility Setup…"))
        }

        @Test func missingAccessibilityOffersSetup() {
            accessibilityGranted = false
            let menu = controller.makeMenu()
            controller.refresh(menu)
            #expect(
                Array(visibleTitles(menu).prefix(2)) == ["Accessibility access needed", "Open Accessibility Setup…"])

            // granting access removes the status rows on the next refresh
            accessibilityGranted = true
            controller.refresh(menu)
            #expect(visibleTitles(menu) == ["Disable", "Settings…", "Quit WindowHop"])
        }

        @Test func buttonLabelCarriesState() {
            let button = NSButton()
            controller.refreshButton(button)
            #expect(button.image?.accessibilityDescription == "WindowHop")

            preferences.switcherEnabled = false
            controller.refreshButton(button)
            #expect(button.image?.accessibilityDescription == StatusItemState.paused.accessibilityLabel)

            accessibilityGranted = false
            controller.refreshButton(button)
            #expect(
                button.image?.accessibilityDescription == StatusItemState.accessibilityRequired.accessibilityLabel)
        }

        @Test func settingsAndQuitAlwaysPresent() {
            let menu = controller.makeMenu()
            controller.refresh(menu)
            #expect(menu.items.contains { $0.title == "Settings…" && !$0.isHidden })
            #expect(menu.items.last?.title == "Quit WindowHop")
        }
    }
}
