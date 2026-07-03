import AppKit
import Carbon.HIToolbox

/// Application lifecycle: permission gating, engine start/stop, settings reactions,
/// and the guarantee that a relaunch opens Settings even with all icons hidden.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private var engineRunning = false

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(preferences.showDockIcon ? .regular : .accessory)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedAsLoginItem = isLoginItemLaunch()
        BackgroundWork.start()
        SwitcherController.shared.wire()
        StatusItemController.shared.apply()
        UpdateManager.shared.startIfBundled()
        observeSystemEvents()

        if AccessibilityPermission.isGranted {
            startEngine()
            completeFirstLaunchIfNeeded()
            if !launchedAsLoginItem {
                SettingsWindowController.shared.show()
            }
        } else {
            showOnboarding()
        }
    }

    /// Relaunching the app (Finder, Spotlight, Dock) reopens Settings.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AccessibilityPermission.isGranted {
            SettingsWindowController.shared.show()
        } else {
            showOnboarding()
        }
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // nothing system-wide to restore: WindowHop never modifies the native switcher
        EventTap.shared.stop()
    }

    // MARK: - Engine

    private func startEngine() {
        guard !engineRunning else { return }
        engineRunning = true
        WindowStore.shared.start()
        applyConfiguration()
    }

    private func stopEngine() {
        guard engineRunning else { return }
        engineRunning = false
        SwitcherController.shared.applyConfiguration(enabled: false, granted: false)
        WindowStore.shared.stop()
    }

    private func applyConfiguration() {
        SwitcherController.shared.applyConfiguration(
            enabled: preferences.switcherEnabled && engineRunning,
            granted: AccessibilityPermission.isGranted)
    }

    // MARK: - Observers

    private func observeSystemEvents() {
        // settings changes (from the Settings window or the menu bar item)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            NSApp.setActivationPolicy(self.preferences.showDockIcon ? .regular : .accessory)
            StatusItemController.shared.apply()
            self.applyConfiguration()
        }
        // permission granted or revoked while running
        AccessibilityPermission.observeChanges { [weak self] granted in
            guard let self else { return }
            if granted {
                PermissionOnboardingController.shared.close()
                self.startEngine()
                self.completeFirstLaunchIfNeeded()
            } else {
                // never partially intercept the shortcut without permission
                self.stopEngine()
                self.showOnboarding()
            }
        }
        // macOS can silently disable event taps across sleep/wake and session switches
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            EventTap.shared.reEnableIfNeeded()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
            EventTap.shared.reEnableIfNeeded()
        }
    }

    private func showOnboarding() {
        PermissionOnboardingController.shared.onGranted = { [weak self] in
            guard let self else { return }
            self.startEngine()
            self.completeFirstLaunchIfNeeded()
            SettingsWindowController.shared.show()
        }
        PermissionOnboardingController.shared.show()
    }

    /// Default: launch at login enabled when it can actually be configured
    /// (requires running from a real .app bundle).
    private func completeFirstLaunchIfNeeded() {
        guard !preferences.firstLaunchCompleted else { return }
        preferences.firstLaunchCompleted = true
        if preferences.launchAtLogin, !LoginItem.isEnabled {
            if !LoginItem.set(true) {
                preferences.launchAtLogin = false
            }
        }
    }

    private func isLoginItemLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
    }
}
