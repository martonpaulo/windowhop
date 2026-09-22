import AppKit

/// App-specific main-menu actions, delivered through the responder chain to
/// the application delegate (which `NSApplication` consults after the key
/// window), so the builder needs no reference to it.
@objc public protocol MainMenuActions {
    /// Opens Settings › About, WindowHop's one About surface.
    func openAboutFromMenu(_ sender: Any?)
    func openSettingsFromMenu(_ sender: Any?)
    func reportIssue(_ sender: Any?)
}

/// Builds WindowHop's main menu. An accessory app has no visible menu bar,
/// but it still needs the menu for the key equivalents of its Settings window
/// (⌘, ⌘Q ⌘W ⌘M and text editing). When the Dock icon setting makes the app
/// regular, the menu bar is visible and also carries the standard regular-app
/// commands: Services, Hide, Hide Others, Show All, Zoom and Help.
///
/// Every item has a `nil` target so the responder chain delivers it. The
/// builder never touches `NSApp`; the caller installs `windowsMenu`,
/// `servicesMenu` and `helpMenu`.
public enum MainMenuBuilder {
    public struct MainMenu {
        public let menu: NSMenu
        public let windowsMenu: NSMenu
        /// Only in regular mode.
        public let servicesMenu: NSMenu?
        /// Only in regular mode.
        public let helpMenu: NSMenu?
    }

    public static func make(isRegular: Bool) -> MainMenu {
        let mainMenu = NSMenu(title: "Main Menu")

        // App menu. Services wiring and placement follow AltTab's
        // src/ui/MainMenu.swift (see UPSTREAM.md).
        let appMenu = NSMenu(title: "WindowHop")
        // opens Settings › About rather than AppKit's standard About panel,
        // so every entry point reaches the same About
        appMenu.addItem(item("About WindowHop", #selector(MainMenuActions.openAboutFromMenu(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(MainMenuActions.openSettingsFromMenu(_:)), ","))
        var servicesMenu: NSMenu?
        if isRegular {
            appMenu.addItem(.separator())
            let services = NSMenu(title: "Services")
            let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            servicesItem.submenu = services
            appMenu.addItem(servicesItem)
            servicesMenu = services
            appMenu.addItem(.separator())
            appMenu.addItem(item("Hide WindowHop", #selector(NSApplication.hide(_:)), "h"))
            appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)),
                                 "h", [.option, .command]))
            appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        }
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit WindowHop", #selector(NSApplication.terminate(_:)), "q"))
        mainMenu.addItem(menuBarItem(appMenu))

        // standard Edit menu so text fields (e.g. the shortcut recorder pane)
        // support the usual editing shortcuts
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", Selector(("undo:")), "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        mainMenu.addItem(menuBarItem(editMenu))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        if isRegular {
            // AppKit disables it for the non-resizable Settings window
            windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        }
        mainMenu.addItem(menuBarItem(windowMenu))

        var helpMenu: NSMenu?
        if isRegular {
            // no "WindowHop Help" item: the project ships no help documentation
            let help = NSMenu(title: "Help")
            help.addItem(item("Report an Issue…", #selector(MainMenuActions.reportIssue(_:))))
            mainMenu.addItem(menuBarItem(help))
            helpMenu = help
        }

        return MainMenu(menu: mainMenu, windowsMenu: windowMenu,
                        servicesMenu: servicesMenu, helpMenu: helpMenu)
    }

    private static func menuBarItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }
}
