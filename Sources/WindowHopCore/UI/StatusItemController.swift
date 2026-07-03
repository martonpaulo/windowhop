import AppKit

/// Optional menu bar item (hidden by default). Menu contains exactly:
/// Enable/Disable, Settings…, Quit.
public final class StatusItemController: NSObject {
    public static let shared = StatusItemController()

    private var statusItem: NSStatusItem?

    public func apply() {
        let shouldShow = Preferences.shared.showMenuBarItem
        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                         accessibilityDescription: "WindowHop")
            item.menu = buildMenu()
            statusItem = item
        } else if !shouldShow, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        refreshMenuTitles()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Disable", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 1
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        if UpdateManager.shared.isAvailable {
            let updatesItem = NSMenuItem(title: "Check for Updates…",
                                         action: #selector(checkForUpdates), keyEquivalent: "")
            updatesItem.target = self
            menu.addItem(updatesItem)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit WindowHop", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func refreshMenuTitles() {
        guard let toggleItem = statusItem?.menu?.item(withTag: 1) else { return }
        toggleItem.title = Preferences.shared.switcherEnabled ? "Disable" : "Enable"
    }

    @objc private func toggleEnabled() {
        Preferences.shared.switcherEnabled.toggle()
        refreshMenuTitles()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
