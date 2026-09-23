import AppKit
import Testing

@testable import WindowHopCore

extension SharedAppState {
    /// The main menu for both activation policies: accessory mode keeps exactly
    /// the Settings-window key equivalents, regular mode (Dock icon on) adds the
    /// standard regular-app commands. Built without touching `NSApp`.
    @MainActor
    struct MainMenuBuilderTests {
        private struct Entry: Equatable {
            let title: String
            let action: String?
            let key: String
            let modifiers: NSEvent.ModifierFlags.RawValue
        }

        private func entries(_ menu: NSMenu) -> [Entry] {
            menu.items.filter { !$0.isSeparatorItem }.map {
                Entry(
                    title: $0.title, action: $0.action.map(NSStringFromSelector), key: $0.keyEquivalent,
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

        @Test func accessoryModeKeepsTheSettingsWindowCommands() throws {
            let built = MainMenuBuilder.make(isRegular: false)
            #expect(built.menu.items.compactMap { $0.submenu?.title } == ["WindowHop", "Edit", "Window"])
            #expect(
                entries(try #require(submenu(built, "WindowHop"))) == [
                    Entry(title: "About WindowHop", action: "openAboutFromMenu:", key: "", modifiers: 0),
                    Entry(title: "Settings…", action: "openSettingsFromMenu:", key: ",", modifiers: command),
                    Entry(title: "Quit WindowHop", action: "terminate:", key: "q", modifiers: command),
                ])
            #expect(
                entries(try #require(submenu(built, "Edit"))) == [
                    Entry(title: "Undo", action: "undo:", key: "z", modifiers: command),
                    Entry(title: "Redo", action: "redo:", key: "Z", modifiers: command),
                    Entry(title: "Cut", action: "cut:", key: "x", modifiers: command),
                    Entry(title: "Copy", action: "copy:", key: "c", modifiers: command),
                    Entry(title: "Paste", action: "paste:", key: "v", modifiers: command),
                    Entry(title: "Select All", action: "selectAll:", key: "a", modifiers: command),
                ])
            #expect(
                entries(try #require(submenu(built, "Window"))) == [
                    Entry(title: "Close", action: "performClose:", key: "w", modifiers: command),
                    Entry(title: "Minimize", action: "performMiniaturize:", key: "m", modifiers: command),
                ])
            #expect(built.servicesMenu == nil)
            #expect(built.helpMenu == nil)
            #expect(built.windowsMenu === submenu(built, "Window"))
        }

        @Test func regularModeAddsStandardAppCommands() throws {
            let built = MainMenuBuilder.make(isRegular: true)
            #expect(
                built.menu.items.compactMap { $0.submenu?.title } == ["WindowHop", "Edit", "Window", "Help"])

            let appMenu = try #require(submenu(built, "WindowHop"))
            #expect(
                entries(appMenu).map(\.title) == [
                    "About WindowHop", "Settings…", "Services",
                    "Hide WindowHop", "Hide Others", "Show All", "Quit WindowHop",
                ])
            let services = try #require(appMenu.items.first { $0.title == "Services" })
            #expect(services.submenu != nil)
            #expect(services.submenu === built.servicesMenu)
            #expect(
                entries(appMenu).contains(
                    Entry(title: "Hide WindowHop", action: "hide:", key: "h", modifiers: command)))
            #expect(
                entries(appMenu).contains(
                    Entry(
                        title: "Hide Others", action: "hideOtherApplications:", key: "h",
                        modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue)))
            #expect(
                entries(appMenu).contains(
                    Entry(title: "Show All", action: "unhideAllApplications:", key: "", modifiers: 0)))
            #expect(entries(appMenu).last?.title == "Quit WindowHop")

            let windowMenu = try #require(submenu(built, "Window"))
            #expect(entries(windowMenu).map(\.action) == ["performClose:", "performMiniaturize:", "performZoom:"])

            let help = try #require(built.helpMenu)
            #expect(help === submenu(built, "Help"))
            #expect(
                entries(help) == [
                    Entry(title: "Report an Issue…", action: "reportIssue:", key: "", modifiers: 0)
                ])
        }

        @Test func everyItemUsesTheResponderChain() {
            for isRegular in [false, true] {
                // items holding a submenu get the submenu as target from AppKit
                for item in allItems(MainMenuBuilder.make(isRegular: isRegular).menu) where item.submenu == nil {
                    #expect(item.target == nil, "\(item.title) (regular: \(isRegular))")
                }
            }
        }

        @Test func exactlyOneAboutItemInBothModes() {
            for isRegular in [false, true] {
                let abouts = allItems(MainMenuBuilder.make(isRegular: isRegular).menu)
                    .filter { $0.title.hasPrefix("About") }
                #expect(abouts.count == 1, "regular: \(isRegular)")
            }
        }

        @Test func appDelegateHandlesTheAppSpecificActions() {
            // the nil-target items reach the delegate only if it implements them
            let delegate = AppDelegate()
            #expect(delegate.responds(to: #selector(MainMenuActions.openAboutFromMenu(_:))))
            #expect(delegate.responds(to: #selector(MainMenuActions.openSettingsFromMenu(_:))))
            #expect(delegate.responds(to: #selector(MainMenuActions.reportIssue(_:))))
        }
    }
}
