import AppKit
import WindowHopKit

/// Optional menu bar item (hidden by default). Its symbol shape and
/// accessibility label show `StatusItemState` (active, paused, Accessibility
/// required). The menu contains exactly: a status row, plus Open
/// Accessibility Setup… when Accessibility is missing (both only when not
/// active); Enable/Disable, Settings…, Check for Updates… (only while the
/// updater runs, i.e. in a bundled build), Quit.
///
/// The menu is built once with every item present and brought up to date by
/// `refresh(_:)` — on `apply()` (every settings write and every Accessibility
/// grant change) and each time the menu opens — so its contents never depend
/// on whether the updater started before or after the item was created.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    enum ItemTag: Int {
        case toggle = 1
        case checkForUpdates
        case status
        case accessibilitySetup
        case statusSeparator
    }

    private let preferences: Preferences
    private let accessibilityGranted: () -> Bool
    private let updaterAvailable: () -> Bool
    private let canCheckForUpdates: () -> Bool
    private let actions: Actions
    private var statusItem: NSStatusItem?

    /// What the menu's commands open or start; `AppDelegate` supplies the
    /// objects it owns.
    public struct Actions {
        let openAccessibilitySetup: () -> Void
        let openSettings: () -> Void
        let checkForUpdates: () -> Void

        public init(openAccessibilitySetup: @escaping () -> Void,
                    openSettings: @escaping () -> Void,
                    checkForUpdates: @escaping () -> Void) {
            self.openAccessibilitySetup = openAccessibilitySetup
            self.openSettings = openSettings
            self.checkForUpdates = checkForUpdates
        }
    }

    public init(preferences: Preferences,
                accessibilityGranted: @escaping () -> Bool,
                updaterAvailable: @escaping () -> Bool,
                canCheckForUpdates: @escaping () -> Bool,
                actions: Actions) {
        self.preferences = preferences
        self.accessibilityGranted = accessibilityGranted
        self.updaterAvailable = updaterAvailable
        self.canCheckForUpdates = canCheckForUpdates
        self.actions = actions
        super.init()
    }

    public func apply() {
        let shouldShow = preferences.showMenuBarItem
        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.menu = makeMenu()
            statusItem = item
        } else if !shouldShow, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        refreshStatusItem()
    }

    var state: StatusItemState {
        StatusItemState.resolve(switcherEnabled: preferences.switcherEnabled,
                                accessibilityGranted: accessibilityGranted())
    }

    private func refreshStatusItem() {
        if let button = statusItem?.button {
            refreshButton(button)
        }
        if let menu = statusItem?.menu {
            refresh(menu)
        }
    }

    /// The symbol's shape and its accessibility description both carry the
    /// state, so it reads without color and without opening the menu.
    func refreshButton(_ button: NSButton) {
        let state = state
        button.image = NSImage(systemSymbolName: state.symbolName,
                               accessibilityDescription: state.accessibilityLabel)
    }

    /// Builds the item's menu once, with every item it can ever show.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // no action: AppKit shows it disabled, as plain text VoiceOver reads
        let statusRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusRow.tag = ItemTag.status.rawValue
        statusRow.isHidden = true
        menu.addItem(statusRow)
        let setupItem = NSMenuItem(title: String(localized: "Open Accessibility Setup…"),
                                   action: #selector(openAccessibilitySetup), keyEquivalent: "")
        setupItem.target = self
        setupItem.tag = ItemTag.accessibilitySetup.rawValue
        setupItem.isHidden = true
        menu.addItem(setupItem)
        let statusSeparator = NSMenuItem.separator()
        statusSeparator.tag = ItemTag.statusSeparator.rawValue
        statusSeparator.isHidden = true
        menu.addItem(statusSeparator)
        let toggleItem = NSMenuItem(title: String(localized: "Disable"),
                                    action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = ItemTag.toggle.rawValue
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"),
                                      action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let updatesItem = NSMenuItem(title: String(localized: "Check for Updates…"),
                                     action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.tag = ItemTag.checkForUpdates.rawValue
        updatesItem.isHidden = true
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: String(localized: "Quit WindowHop"),
                                  action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    /// Brings the menu's titles and visibility up to the current state.
    /// Idempotent: it only mutates existing items, never adds any.
    func refresh(_ menu: NSMenu) {
        let state = state
        if let statusRow = menu.item(withTag: ItemTag.status.rawValue) {
            statusRow.title = state.statusText ?? ""
            statusRow.isHidden = state.statusText == nil
        }
        menu.item(withTag: ItemTag.accessibilitySetup.rawValue)?.isHidden = !state.offersAccessibilitySetup
        menu.item(withTag: ItemTag.statusSeparator.rawValue)?.isHidden = state.statusText == nil
        menu.item(withTag: ItemTag.toggle.rawValue)?.title =
            preferences.switcherEnabled ? String(localized: "Disable") : String(localized: "Enable")
        // a development build has no updater: hide the command rather than
        // offering one that does nothing
        menu.item(withTag: ItemTag.checkForUpdates.rawValue)?.isHidden = !updaterAvailable()
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        refresh(menu)
        if menu === statusItem?.menu, let button = statusItem?.button {
            refreshButton(button)
        }
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
        refreshStatusItem()
    }

    @objc private func openAccessibilitySetup() {
        // the existing recovery surface; AppDelegate sets its onGranted
        // whenever permission is missing
        actions.openAccessibilitySetup()
    }

    @objc private func openSettings() {
        actions.openSettings()
    }

    @objc private func checkForUpdates() {
        actions.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
