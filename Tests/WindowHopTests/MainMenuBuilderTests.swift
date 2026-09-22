import AppKit
import XCTest
@testable import WindowHopCore

/// The main menu for both activation policies: accessory mode keeps exactly
/// the Settings-window key equivalents, regular mode (Dock icon on) adds the
/// standard regular-app commands. Built without touching `NSApp`.
final class MainMenuBuilderTests: XCTestCase {
    private struct Entry: Equatable {
        let title: String
        let action: String?
        let key: String
        let modifiers: NSEvent.ModifierFlags.RawValue
    }

    private func entries(_ menu: NSMenu) -> [Entry] {
        menu.items.filter { !$0.isSeparatorItem }.map {
            Entry(title: $0.title, action: $0.action.map(NSStringFromSelector), key: $0.keyEquivalent,
                  modifiers: $0.keyEquivalent.isEmpty ? 0 : $0.keyEquivalentModifierMask.rawValue)
        }
    }

    private func submenu(_ built: MainMenuBuilder.MainMenu, _ title: String) -> NSMenu? {
        built.menu.items.first { $0.submenu?.title == title }?.submenu
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }

    private let command = NSEvent.ModifierFlags.command.rawValue

    func testAccessoryModeKeepsTheSettingsWindowCommands() throws {
        let built = MainMenuBuilder.make(isRegular: false)
        XCTAssertEqual(built.menu.items.compactMap { $0.submenu?.title }, ["WindowHop", "Edit", "Window"])
        XCTAssertEqual(entries(try XCTUnwrap(submenu(built, "WindowHop"))), [
            Entry(title: "About WindowHop", action: "orderFrontStandardAboutPanel:", key: "", modifiers: 0),
            Entry(title: "Settings…", action: "openSettingsFromMenu:", key: ",", modifiers: command),
            Entry(title: "Quit WindowHop", action: "terminate:", key: "q", modifiers: command),
        ])
        XCTAssertEqual(entries(try XCTUnwrap(submenu(built, "Edit"))), [
            Entry(title: "Undo", action: "undo:", key: "z", modifiers: command),
            Entry(title: "Redo", action: "redo:", key: "Z", modifiers: command),
            Entry(title: "Cut", action: "cut:", key: "x", modifiers: command),
            Entry(title: "Copy", action: "copy:", key: "c", modifiers: command),
            Entry(title: "Paste", action: "paste:", key: "v", modifiers: command),
            Entry(title: "Select All", action: "selectAll:", key: "a", modifiers: command),
        ])
        XCTAssertEqual(entries(try XCTUnwrap(submenu(built, "Window"))), [
            Entry(title: "Close", action: "performClose:", key: "w", modifiers: command),
            Entry(title: "Minimize", action: "performMiniaturize:", key: "m", modifiers: command),
        ])
        XCTAssertNil(built.servicesMenu)
        XCTAssertNil(built.helpMenu)
        XCTAssertTrue(built.windowsMenu === submenu(built, "Window"))
    }

    func testRegularModeAddsStandardAppCommands() throws {
        let built = MainMenuBuilder.make(isRegular: true)
        XCTAssertEqual(built.menu.items.compactMap { $0.submenu?.title },
                       ["WindowHop", "Edit", "Window", "Help"])

        let appMenu = try XCTUnwrap(submenu(built, "WindowHop"))
        XCTAssertEqual(entries(appMenu).map(\.title), [
            "About WindowHop", "Settings…", "Services",
            "Hide WindowHop", "Hide Others", "Show All", "Quit WindowHop",
        ])
        let services = try XCTUnwrap(appMenu.items.first { $0.title == "Services" })
        XCTAssertNotNil(services.submenu)
        XCTAssertTrue(services.submenu === built.servicesMenu)
        XCTAssertTrue(entries(appMenu).contains(
            Entry(title: "Hide WindowHop", action: "hide:", key: "h", modifiers: command)))
        XCTAssertTrue(entries(appMenu).contains(
            Entry(title: "Hide Others", action: "hideOtherApplications:", key: "h",
                  modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue)))
        XCTAssertTrue(entries(appMenu).contains(
            Entry(title: "Show All", action: "unhideAllApplications:", key: "", modifiers: 0)))
        XCTAssertEqual(entries(appMenu).last?.title, "Quit WindowHop")

        let windowMenu = try XCTUnwrap(submenu(built, "Window"))
        XCTAssertEqual(entries(windowMenu).map(\.action), ["performClose:", "performMiniaturize:", "performZoom:"])

        let help = try XCTUnwrap(built.helpMenu)
        XCTAssertTrue(help === submenu(built, "Help"))
        XCTAssertEqual(entries(help), [
            Entry(title: "Report an Issue…", action: "reportIssue:", key: "", modifiers: 0),
        ])
    }

    func testEveryItemUsesTheResponderChain() {
        for isRegular in [false, true] {
            // items holding a submenu get the submenu as target from AppKit
            for item in allItems(MainMenuBuilder.make(isRegular: isRegular).menu) where item.submenu == nil {
                XCTAssertNil(item.target, "\(item.title) (regular: \(isRegular))")
            }
        }
    }

    func testExactlyOneAboutItemInBothModes() {
        for isRegular in [false, true] {
            let abouts = allItems(MainMenuBuilder.make(isRegular: isRegular).menu)
                .filter { $0.title.hasPrefix("About") }
            XCTAssertEqual(abouts.count, 1, "regular: \(isRegular)")
        }
    }

    func testAppDelegateHandlesTheAppSpecificActions() {
        // the nil-target items reach the delegate only if it implements them
        let delegate = AppDelegate()
        XCTAssertTrue(delegate.responds(to: #selector(MainMenuActions.openSettingsFromMenu(_:))))
        XCTAssertTrue(delegate.responds(to: #selector(MainMenuActions.reportIssue(_:))))
    }
}
