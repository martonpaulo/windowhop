import AppKit
import ApplicationServices

/// A window entry as consumed by the switcher UI: plain values plus a reference
/// for actions (activate/close). `id` is the stable identity used to match entries
/// across snapshots while the switcher is open.
public struct SwitcherItem {
    public let id: AnyHashable
    public let window: TrackedWindow?
    public let title: String
    public let appName: String
    public let icon: NSImage?
    public let tabCount: Int?

    public init(id: AnyHashable, window: TrackedWindow?, title: String,
                appName: String, icon: NSImage?, tabCount: Int?) {
        self.id = id
        self.window = window
        self.title = title
        self.appName = appName
        self.icon = icon
        self.tabCount = tabCount
    }
}

/// Main-thread source of truth: every tracked app and window, in window-level MRU order
/// (index 0 = currently focused window). Event-driven only — AX notifications,
/// NSWorkspace notifications, and KVO; nothing polls.
public final class WindowStore {
    public static let shared = WindowStore()

    public private(set) var apps: [pid_t: TrackedApp] = [:]
    /// MRU order: index 0 is the focused window.
    public private(set) var windows: [TrackedWindow] = []
    /// Fired on any change that can affect the visible list.
    public var onChange: (() -> Void)?

    private var preferences: Preferences { Preferences.shared }
    private var runningAppsObserver: NSKeyValueObservation?
    private var started = false

    /// Requires Accessibility permission. Safe to call again after stop().
    public func start() {
        guard !started else { return }
        started = true
        AXUIElement.setGlobalTimeout()
        runningAppsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { _, change in
            DispatchQueue.main.async { [weak self] in
                (change.newValue ?? []).forEach { self?.addApp($0) }
                (change.oldValue ?? []).forEach { self?.removeApp($0.processIdentifier) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.runningApplications.forEach { addApp($0) }
    }

    public func stop() {
        guard started else { return }
        started = false
        runningAppsObserver = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        apps.values.forEach { $0.stopObserving() }
        apps = [:]
        windows = []
        onChange?()
    }

    // MARK: - App lifecycle

    private func addApp(_ runningApplication: NSRunningApplication) {
        let pid = runningApplication.processIdentifier
        guard started, pid != ProcessInfo.processInfo.processIdentifier, pid > 0,
              apps[pid] == nil, !runningApplication.isTerminated else { return }
        apps[pid] = TrackedApp(runningApplication)
    }

    private func removeApp(_ pid: pid_t) {
        guard let app = apps[pid], app.runningApplication.isTerminated else { return }
        app.stopObserving()
        apps[pid] = nil
        let hadWindows = windows.contains { $0.app === app }
        windows.removeAll { $0.app === app }
        if hadWindows {
            onChange?()
        }
    }

    func appActivated(pid: pid_t) {
        // no list change by itself; the focused-window event that follows updates MRU
        _ = apps[pid]
    }

    func appHiddenChanged(pid: pid_t, isHidden: Bool) {
        guard let app = apps[pid] else { return }
        app.isHidden = isHidden
        onChange?()
    }

    // MARK: - Window discovery and events

    /// Enumerates an app's current windows on the AX reads queue. Called when an app
    /// becomes observable and again on Space changes (public AX only returns windows
    /// of the current Space; re-enumerating on Space change builds the full inventory).
    func discoverWindows(of app: TrackedApp) {
        let element = app.axElement
        let pid = app.pid
        BackgroundWork.axReadsQueue.async {
            guard let elements = try? element.windowElements() else { return }
            for windowElement in elements {
                AXNotificationRouter.routeWindowEvent(kAXWindowCreatedNotification, windowElement, pid)
            }
            // seed MRU: the frontmost app's focused window belongs at the front
            if app.runningApplication.isActive,
               let focused = (try? element.attributes([kAXFocusedWindowAttribute]))?.focusedWindow {
                AXNotificationRouter.routeWindowEvent(kAXFocusedWindowChangedNotification, focused, pid)
            }
        }
    }

    func windowEvent(_ notification: String, element: AXUIElement, pid: pid_t,
                     attributes: AXAttributes, tabCount: Int?) {
        guard started, let app = apps[pid] else { return }
        let existing = windows.first { $0.ax == element }
        let window: TrackedWindow
        if let existing {
            existing.update(from: attributes, tabCount: tabCount)
            window = existing
        } else {
            let facts = app.windowFacts(from: attributes)
            let isFocusEvent = notification == kAXFocusedWindowChangedNotification
                || notification == kAXMainWindowChangedNotification
            // unknown non-windows (menus, tooltips, …) are ignored entirely, but a window
            // that just got focused is real even if its subrole looks wrong mid-animation
            guard WindowEligibility.isActualWindow(facts) || isFocusEvent else { return }
            window = TrackedWindow(ax: element, app: app, attributes: attributes, tabCount: tabCount)
            windows.append(window)
            BackgroundWork.axReadsQueue.async {
                app.subscribeToWindowNotifications(element)
            }
        }
        switch notification {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            // Photoshop focuses a window after you focus another app; ignore those
            if app.runningApplication.isActive {
                window.isOnCurrentSpace = true
                windowFocused(window)
            }
        case kAXWindowMiniaturizedNotification:
            window.isMinimized = true
        case kAXWindowDeminiaturizedNotification:
            window.isMinimized = false
        default:
            break
        }
        onChange?()
    }

    private func windowFocused(_ window: TrackedWindow) {
        if let index = windows.firstIndex(where: { $0 === window }), index != 0 {
            windows.remove(at: index)
            windows.insert(window, at: 0)
        }
    }

    func removeWindow(_ element: AXUIElement) {
        guard let index = windows.firstIndex(where: { $0.ax == element }) else { return }
        windows.remove(at: index)
        onChange?()
    }

    /// Re-enumerate every app on Space change: discovers windows we could not see
    /// before (other-Space windows enter kAXWindows once their Space is visited) and
    /// updates each window's current-Space flag.
    @objc private func activeSpaceChanged() {
        let appsSnapshot = Array(apps.values)
        BackgroundWork.axReadsQueue.async {
            for app in appsSnapshot {
                let elements = (try? app.axElement.windowElements()) ?? []
                for windowElement in elements {
                    AXNotificationRouter.routeWindowEvent(kAXWindowCreatedNotification, windowElement, app.pid)
                }
                let currentElements = Set(elements)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    for window in self.windows where window.app === app {
                        window.isOnCurrentSpace = currentElements.contains(window.ax)
                    }
                    self.onChange?()
                }
            }
        }
    }

    // MARK: - Snapshot

    /// The visible, ordered switcher list under the current settings.
    public func snapshot() -> [SwitcherItem] {
        let includeOtherSpaces = preferences.includeOtherSpaces
        let includeOtherDisplays = preferences.includeOtherDisplays
        let showTabCounts = preferences.showTabCounts
        let activeScreen = NSScreen.main
        return windows.compactMap { window in
            guard window.isActual else { return nil }
            let state = WindowDisplayState(
                isMinimized: window.isMinimized,
                isAppHidden: window.app.isHidden,
                isOwnWindow: false, // own windows are never tracked (own pid is excluded)
                isOnCurrentSpace: window.isOnCurrentSpace,
                isOnActiveDisplay: activeScreen.map { window.isOn(screen: $0) } ?? true)
            guard WindowEligibility.shouldDisplay(state,
                                                  includeOtherSpaces: includeOtherSpaces,
                                                  includeOtherDisplays: includeOtherDisplays) else { return nil }
            return SwitcherItem(id: ObjectIdentifier(window),
                                window: window,
                                title: window.title,
                                appName: window.app.name ?? "",
                                icon: window.app.icon,
                                tabCount: showTabCounts ? window.tabCount : nil)
        }
    }
}
