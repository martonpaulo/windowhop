import AppKit

/// Optional menu bar item (hidden by default). Menu contains exactly:
/// Enable/Disable, Settings…, Check for Updates… (only while the updater
/// runs, i.e. in a bundled build), Quit.
///
/// The menu is built once with every item present and brought up to date by
/// `refresh(_:)` — on `apply()` and each time the menu opens — so its
/// contents never depend on whether the updater started before or after the
/// item was created.
public final class StatusItemController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    public static let shared = StatusItemController(
        preferences: .shared,
        updaterAvailable: { UpdateManager.shared.isAvailable },
        canCheckForUpdates: { UpdateManager.shared.canCheckForUpdates })

    enum ItemTag: Int {
        case toggle = 1
        case checkForUpdates
    }

    private let preferences: Preferences
    private let updaterAvailable: () -> Bool
    private let canCheckForUpdates: () -> Bool
    private var statusItem: NSStatusItem?

    init(preferences: Preferences,
         updaterAvailable: @escaping () -> Bool,
         canCheckForUpdates: @escaping () -> Bool) {
        self.preferences = preferences
        self.updaterAvailable = updaterAvailable
        self.canCheckForUpdates = canCheckForUpdates
        super.init()
    }

    public func apply() {
        let shouldShow = preferences.showMenuBarItem
        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                         accessibilityDescription: "WindowHop")
            item.menu = makeMenu()
            statusItem = item
        } else if !shouldShow, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        if let menu = statusItem?.menu {
            refresh(menu)
        }
    }

    /// Builds the item's menu once, with every item it can ever show.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let toggleItem = NSMenuItem(title: "Disable", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = ItemTag.toggle.rawValue
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let updatesItem = NSMenuItem(title: "Check for Updates…",
                                     action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.tag = ItemTag.checkForUpdates.rawValue
        updatesItem.isHidden = true
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit WindowHop", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    /// Brings the menu's titles and visibility up to the current state.
    /// Idempotent: it only mutates existing items, never adds any.
    func refresh(_ menu: NSMenu) {
        menu.item(withTag: ItemTag.toggle.rawValue)?.title =
            preferences.switcherEnabled ? "Disable" : "Enable"
        // a development build has no updater: hide the command rather than
        // offering one that does nothing
        menu.item(withTag: ItemTag.checkForUpdates.rawValue)?.isHidden = !updaterAvailable()
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        refresh(menu)
    }

    // MARK: - NSMenuItemValidation

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            // Sparkle's own state: false while a check or an install is in progress
            return canCheckForUpdates()
        }
        return true
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        preferences.switcherEnabled.toggle()
        if let menu = statusItem?.menu {
            refresh(menu)
        }
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
