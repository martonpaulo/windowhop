import AppKit
import XCTest
@testable import WindowHopCore

/// The menu bar item's menu, exercised without creating an `NSStatusItem`:
/// its contents must not depend on whether the updater started before or
/// after the menu was built, and refreshing it must never duplicate items.
final class StatusItemMenuTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var updaterAvailable = false
    private var canCheck = false
    private var controller: StatusItemController!

    override func setUp() {
        super.setUp()
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = Preferences(defaults: defaults)
        updaterAvailable = false
        canCheck = false
        controller = StatusItemController(
            preferences: preferences,
            updaterAvailable: { [unowned self] in self.updaterAvailable },
            canCheckForUpdates: { [unowned self] in self.canCheck })
    }

    override func tearDown() {
        controller = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
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

    func testSettingsAndQuitAlwaysPresent() {
        let menu = controller.makeMenu()
        controller.refresh(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Settings…" && !$0.isHidden })
        XCTAssertEqual(menu.items.last?.title, "Quit WindowHop")
    }
}
