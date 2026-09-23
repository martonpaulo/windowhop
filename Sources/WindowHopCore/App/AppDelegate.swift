import AppKit
import Carbon.HIToolbox
import WindowHopKit

/// Application lifecycle: permission gating, engine start/stop, settings reactions,
/// and the launch/reopen surface decided by `LaunchPresentation` (reopening always
/// reaches Settings or onboarding, so hidden icons are never a dead end).
///
/// The composition root: it creates every long-lived object once and passes
/// each one to its consumers (docs/architecture.md › Composition root).
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, MainMenuActions {
    private let preferences: Preferences
    private let store: WindowStore
    private let tap: EventTap
    private let switcher: SwitcherController
    private let updateManager: UpdateManager
    private let settingsWindow: SettingsWindowController
    private let onboarding: PermissionOnboardingController
    private let statusItem: StatusItemController
    private var engineRunning = false
    private var menuIsRegular: Bool?

    override public init() {
        let preferences = Preferences()
        let previews = PreviewProvider(preferences: preferences)
        let store = WindowStore(preferences: preferences, previews: previews)
        let tap = EventTap()
        let updateManager = UpdateManager(preferences: preferences)
        let settingsWindow = SettingsWindowController(
            dependencies: SettingsDependencies(
                preferences: preferences,
                restorer: SettingsDefaultsRestorer(
                    preferences: preferences,
                    applyAutomaticUpdateChecks: { updateManager.automaticallyChecksForUpdates = $0 }),
                updateManager: updateManager,
                // while the recorder records, the tap passes every key in `watching`,
                // so pressing an already-active chord reaches the recorder
                setShortcutRecordingActive: { tap.isRecordingShortcut = $0 },
                evictPreviews: { previews.evictAll() }),
            registerOwnWindow: { store.registerOwnWindow($0) })
        let onboarding = PermissionOnboardingController()
        self.preferences = preferences
        self.store = store
        self.tap = tap
        switcher = SwitcherController(preferences: preferences, store: store, previews: previews,
                                      tap: tap, showSettings: { settingsWindow.show() })
        self.updateManager = updateManager
        self.settingsWindow = settingsWindow
        self.onboarding = onboarding
        statusItem = StatusItemController(
            preferences: preferences,
            accessibilityGranted: { AccessibilityPermission.isGranted },
            updaterAvailable: { updateManager.isAvailable },
            canCheckForUpdates: { updateManager.canCheckForUpdates },
            actions: StatusItemController.Actions(
                openAccessibilitySetup: { onboarding.show() },
                openSettings: { settingsWindow.show() },
                checkForUpdates: { updateManager.checkForUpdates() }))
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
    }

    /// The Dock icon setting decides regular vs accessory; the main menu is
    /// rebuilt only when that value actually changes, not on every
    /// unrelated settings write.
    private func applyActivationPolicy() {
        let isRegular = preferences.showDockIcon
        NSApp.setActivationPolicy(isRegular ? .regular : .accessory)
        guard isRegular != menuIsRegular else { return }
        menuIsRegular = isRegular
        // agent apps have no nib-provided menu; without one, standard key
        // equivalents (⌘W to close Settings, ⌘Q, ⌘, and text editing) don't work
        let built = MainMenuBuilder.make(isRegular: isRegular)
        NSApp.mainMenu = built.menu
        NSApp.windowsMenu = built.windowsMenu
        NSApp.servicesMenu = built.servicesMenu
        NSApp.helpMenu = built.helpMenu
    }

    @objc public func openAboutFromMenu(_ sender: Any?) {
        settingsWindow.showAbout()
    }

    @objc public func openSettingsFromMenu(_ sender: Any?) {
        settingsWindow.show()
    }

    @objc public func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(ProjectLinks.issueReport(
            for: AppVersion.main, macOS: ProcessInfo.processInfo.operatingSystemVersion))
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let trigger: LaunchPresentation.Trigger =
            isLoginItemLaunch() ? .loginItemLaunch : .normalLaunch
        // read before completeFirstLaunchIfNeeded() marks the first run done
        let isFirstRun = !preferences.firstLaunchCompleted
        ShortcutFormatter.keyLabels = KeyboardLayout.current
        BackgroundWork.start()
        switcher.wire()
        statusItem.apply()
        updateManager.startIfBundled()
        observeSystemEvents()

        let granted = AccessibilityPermission.isGranted
        if granted {
            startEngine()
            completeFirstLaunchIfNeeded()
        }
        present(trigger: trigger, granted: granted, isFirstRun: isFirstRun)
    }

    /// Opening the app again (Finder, Spotlight, Dock) is the route back when both
    /// icons are hidden: Settings, or onboarding while Accessibility is missing.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        present(trigger: .reopen, granted: AccessibilityPermission.isGranted,
                isFirstRun: !preferences.firstLaunchCompleted)
        return false
    }

    private func present(trigger: LaunchPresentation.Trigger, granted: Bool, isFirstRun: Bool) {
        let presentation = LaunchPresentation.decide(
            trigger: trigger,
            permissionGranted: granted,
            isFirstRun: isFirstRun,
            menuBarItemVisible: preferences.showMenuBarItem,
            dockIconVisible: preferences.showDockIcon)
        switch presentation {
        case .none:
            break
        case .settings:
            settingsWindow.show()
        case .onboarding:
            showOnboarding()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // nothing system-wide to restore: WindowHop never modifies the native switcher
        tap.stop()
    }

    // MARK: - Engine

    private func startEngine() {
        guard !engineRunning else { return }
        engineRunning = true
        store.start()
        applyConfiguration()
    }

    private func stopEngine() {
        guard engineRunning else { return }
        engineRunning = false
        switcher.applyConfiguration(enabled: false, granted: false)
        store.stop()
    }

    private func applyConfiguration() {
        switcher.applyConfiguration(
            enabled: preferences.switcherEnabled && engineRunning,
            granted: AccessibilityPermission.isGranted)
    }

    // MARK: - Observers

    private func observeSystemEvents() {
        // settings changes (from the Settings window or the menu bar item)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyActivationPolicy()
                self.statusItem.apply()
                self.applyConfiguration()
            }
        }
        NotificationCenter.default.addObserver(
            forName: Preferences.windowFiltersDidChange,
            object: preferences,
            queue: .main) { [store] _ in
                MainActor.assumeIsolated { store.windowFiltersChanged() }
            }
        // permission granted or revoked while running
        AccessibilityPermission.observeChanges { [weak self] granted in
            guard let self else { return }
            if granted {
                onboarding.close()
                self.startEngine()
                self.completeFirstLaunchIfNeeded()
            } else {
                // never partially intercept the shortcut without permission
                self.stopEngine()
                self.showOnboarding()
            }
            // the menu bar item shows the permission state
            self.statusItem.apply()
        }
        // macOS can silently disable event taps across sleep/wake and session switches
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [tap] _ in
            MainActor.assumeIsolated { tap.reEnableIfNeeded() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main) { [tap] _ in
                MainActor.assumeIsolated { tap.reEnableIfNeeded() }
            }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [tap] _ in
            MainActor.assumeIsolated { tap.reEnableIfNeeded() }
        }
    }

    private func showOnboarding() {
        onboarding.onGranted = { [weak self] in
            guard let self else { return }
            self.startEngine()
            self.completeFirstLaunchIfNeeded()
            settingsWindow.show()
        }
        onboarding.show()
    }

    /// Registers the login item only when the launch-at-login intent is on
    /// (the default is off, see `Preferences.Defaults`) and it can actually be
    /// configured (requires running from a real .app bundle). An existing
    /// registration, including one awaiting approval, is left as it is.
    private func completeFirstLaunchIfNeeded() {
        guard !preferences.firstLaunchCompleted else { return }
        preferences.firstLaunchCompleted = true
        if preferences.launchAtLogin, LoginItem.status == .disabled {
            if LoginItem.set(true).failed {
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
