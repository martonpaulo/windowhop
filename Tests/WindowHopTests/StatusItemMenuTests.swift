import AppKit
import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// The menu bar item's menu, exercised without creating an `NSStatusItem`:
/// its contents must not depend on whether the updater started before or
/// after the menu was built, and refreshing it must never duplicate items.
@MainActor
final class StatusItemMenuTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var accessibilityGranted = true
    private var updaterAvailable = false
    private var canCheck = false
    private var controller: StatusItemController!

    override func setUp() async throws {
        try await super.setUp()
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
            canCheckForUpdates: { [unowned self] in self.canCheck })
    }

    override func tearDown() async throws {
        controller = nil
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func updateItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == "Check for Updates…" }
    }

    func testUpdateCommandAppearsWhenUpdaterStartsAfterMenuWasBuilt() throws {
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertEqual(updateItem(in: menu)?.isHidden, true)

        updaterAvailable = true
        canCheck = true
        // what AppKit does when the menu opens
        menu.delegate?.menuNeedsUpdate?(menu)

        let item = try XCTUnwrap(updateItem(in: menu))
        XCTAssertFalse(item.isHidden)
        XCTAssertTrue(controller.validateMenuItem(item))
    }

    func testUpdateCommandHiddenWithoutUpdater() {
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertEqual(updateItem(in: menu)?.isHidden, true)
    }

    func testUpdateCommandDisabledWhileSparkleCannotCheck() throws {
        updaterAvailable = true
        canCheck = false
        let menu = controller.makeMenu()
        controller.refresh(menu)
        let item = try XCTUnwrap(updateItem(in: menu))
        XCTAssertFalse(item.isHidden)
        XCTAssertFalse(controller.validateMenuItem(item))
    }

    func testRepeatedRefreshNeverDuplicatesItems() {
        updaterAvailable = true
        let menu = controller.makeMenu()
        let countBefore = menu.items.count
        for _ in 0..<3 { controller.refresh(menu) }
        XCTAssertEqual(menu.items.count, countBefore)
        XCTAssertEqual(menu.items.filter { $0.title == "Check for Updates…" }.count, 1)
        XCTAssertEqual(menu.items.filter { ["Enable", "Disable"].contains($0.title) }.count, 1)
    }

    func testToggleTitleFollowsSwitcherEnabled() {
        let menu = controller.makeMenu()
        preferences.switcherEnabled = false
        controller.refresh(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Enable" })
        preferences.switcherEnabled = true
        controller.refresh(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Disable" })
    }

    // MARK: - State presentation (#63)

    private func visibleTitles(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
    }

    func testActiveStateShowsNoStatusRow() {
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertEqual(visibleTitles(menu), ["Disable", "Settings…", "Quit WindowHop"])
        XCTAssertEqual(menu.items.first { !$0.isHidden }?.isSeparatorItem, false)
    }

    func testPausedStateShowsDisabledStatusRowFirst() throws {
        preferences.switcherEnabled = false
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertEqual(visibleTitles(menu), ["Paused", "Enable", "Settings…", "Quit WindowHop"])
        let statusRow = try XCTUnwrap(menu.items.first { $0.title == "Paused" })
        XCTAssertNil(statusRow.action)
        XCTAssertFalse(visibleTitles(menu).contains("Open Accessibility Setup…"))
    }

    func testMissingAccessibilityOffersSetup() {
        accessibilityGranted = false
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertEqual(Array(visibleTitles(menu).prefix(2)),
                       ["Accessibility access needed", "Open Accessibility Setup…"])

        // granting access removes the status rows on the next refresh
        accessibilityGranted = true
        controller.refresh(menu)
        XCTAssertEqual(visibleTitles(menu), ["Disable", "Settings…", "Quit WindowHop"])
    }

    func testButtonLabelCarriesState() {
        let button = NSButton()
        controller.refreshButton(button)
        XCTAssertEqual(button.image?.accessibilityDescription, "WindowHop")

        preferences.switcherEnabled = false
        controller.refreshButton(button)
        XCTAssertEqual(button.image?.accessibilityDescription, StatusItemState.paused.accessibilityLabel)

        accessibilityGranted = false
        controller.refreshButton(button)
        XCTAssertEqual(button.image?.accessibilityDescription,
                       StatusItemState.accessibilityRequired.accessibilityLabel)
    }

    func testSettingsAndQuitAlwaysPresent() {
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Settings…" && !$0.isHidden })
        XCTAssertEqual(menu.items.last?.title, "Quit WindowHop")
    }
}
