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
        discardPreviews(of: windows)
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
        let removed = windows.filter { $0.app === app }
        windows.removeAll { $0.app === app }
        if !removed.isEmpty {
            discardPreviews(of: removed)
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
                     attributes: AXAttributes, tabTitles: [String]?) {
        guard started, let app = apps[pid] else { return }
        let existing = windows.first { $0.ax == element }
        let window: TrackedWindow
        if let existing {
            existing.update(from: attributes, tabTitles: tabTitles)
            window = existing
        } else {
            let facts = app.windowFacts(from: attributes)
            let isFocusEvent = notification == kAXFocusedWindowChangedNotification
                || notification == kAXMainWindowChangedNotification
            // unknown non-windows (menus, tooltips, …) are ignored entirely, but a window
            // that just got focused is real even if its subrole looks wrong mid-animation
            guard WindowEligibility.isActualWindow(facts) || isFocusEvent else { return }
            window = TrackedWindow(ax: element, app: app, attributes: attributes, tabTitles: tabTitles)
            windows.append(window)
            BackgroundWork.axReadsQueue.async {
                app.subscribeToWindowNotifications(element)
            }
        }
        updateTabGroup(for: window, tabTitles: tabTitles)
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
        let removed = windows.remove(at: index)
        discardPreviews(of: [removed])
        if let groupIds = removed.tabGroupIds {
            let remaining = windows.filter { $0.app === removed.app }
            applyTabStates(TabGroupResolver.resolveRemoval(
                removedId: removed.stableId,
                groupIds: groupIds,
                remainingWindows: remaining.map(tabDescriptor)))
        }
        onChange?()
    }

    // MARK: - Own Settings window (the one own-process inclusion exception)

    /// Registers WindowHop's own Settings window as a normal switcher entry.
    /// It participates in MRU, is excluded while minimized, disappears on close,
    /// and can never be duplicated. All other own windows stay excluded because
    /// nothing else is ever registered (own AX windows are not tracked at all).
    public func registerOwnWindow(_ window: NSWindow) {
        if let existing = ownEntry(for: window) {
            windowFocused(existing)
            onChange?()
            return
        }
        let entry = TrackedWindow(settingsWindow: window)
        windows.insert(entry, at: 0)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(ownWindowClosed(_:)),
                           name: NSWindow.willCloseNotification, object: window)
        center.addObserver(self, selector: #selector(ownWindowMiniaturizedChanged(_:)),
                           name: NSWindow.didMiniaturizeNotification, object: window)
        center.addObserver(self, selector: #selector(ownWindowMiniaturizedChanged(_:)),
                           name: NSWindow.didDeminiaturizeNotification, object: window)
        center.addObserver(self, selector: #selector(ownWindowFocused(_:)),
                           name: NSWindow.didBecomeKeyNotification, object: window)
        // Dragging Settings to another display can change whether it belongs in
        // an open session's list. The frame itself is read live on snapshot;
        // these only say "look again". Scoped to this one window, removed with
        // the rest on close, and they never poll.
        center.addObserver(self, selector: #selector(ownWindowGeometryChanged(_:)),
                           name: NSWindow.didMoveNotification, object: window)
        center.addObserver(self, selector: #selector(ownWindowGeometryChanged(_:)),
                           name: NSWindow.didResizeNotification, object: window)
        onChange?()
    }

    /// The one removal-to-retention handoff. Every path that drops a window
    /// goes through it, so a removed stable id can never outlive its window in
    /// the preview cache — reopening Settings mints a fresh id each time, and
    /// the old ones would otherwise survive until the appearance changed.
    private func discardPreviews(of removed: [TrackedWindow]) {
        removed.forEach { PreviewProvider.shared.evict($0.stableId) }
    }

    private func ownEntry(for window: NSWindow) -> TrackedWindow? {
        windows.first { $0.isOwnSettingsEntry && $0.nativeWindow === window }
    }

    @objc private func ownWindowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = ownEntry(for: window) else { return }
        NotificationCenter.default.removeObserver(self, name: nil, object: window)
        windows.removeAll { $0 === entry }
        discardPreviews(of: [entry])
        onChange?()
    }

    @objc private func ownWindowMiniaturizedChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = ownEntry(for: window) else { return }
        entry.isMinimized = notification.name == NSWindow.didMiniaturizeNotification
        onChange?()
    }

    @objc private func ownWindowGeometryChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              ownEntry(for: window) != nil else { return }
        onChange?()
    }

    @objc private func ownWindowFocused(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = ownEntry(for: window) else { return }
        windowFocused(entry)
        onChange?()
    }

    // MARK: - Tab groups (tabs are never independent entries)

    private func tabDescriptor(_ window: TrackedWindow)
        -> TabGroupResolver.WindowDescriptor<UUID> {
        TabGroupResolver.WindowDescriptor(id: window.stableId,
                                          title: window.title,
                                          isTabbed: window.isTabbed,
                                          groupIds: window.tabGroupIds)
    }

    private func updateTabGroup(for window: TrackedWindow, tabTitles: [String]?) {
        // cheap fast path: nothing reported and no group membership to maintain
        guard tabTitles != nil || window.tabGroupIds != nil else { return }
        let sameApp = windows.filter { $0.app === window.app && $0 !== window }
        applyTabStates(TabGroupResolver.resolve(active: tabDescriptor(window),
                                                tabTitles: tabTitles,
                                                sameAppWindows: sameApp.map(tabDescriptor)))
    }

    private func applyTabStates(_ changes: [UUID: TabGroupResolver.WindowTabState<UUID>]) {
        guard !changes.isEmpty else { return }
        for window in windows {
            if let change = changes[window.stableId] {
                window.isTabbed = change.isTabbed
                window.tabGroupIds = change.groupIds
            }
        }
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
                    var missing = [AXUIElement]()
                    for window in self.windows where window.app === app {
                        guard let ax = window.ax else { continue }
                        window.isOnCurrentSpace = currentElements.contains(ax)
                        if !window.isOnCurrentSpace {
                            missing.append(ax)
                        }
                    }
                    self.onChange?()
                    // a window absent from kAXWindows is either on another Space
                    // (keep it) or silently dead — a missed destroy notification
                    // once produced duplicate entries. Validate and prune.
                    self.pruneIfDead(missing)
                }
            }
        }
    }

    /// Validates possibly-stale AX elements off the main thread and removes the
    /// dead ones. Cheap (one attribute read per suspect) and strictly event-driven.
    func pruneIfDead(_ elements: [AXUIElement]) {
        guard !elements.isEmpty else { return }
        BackgroundWork.axReadsQueue.async {
            let dead = elements.filter { !$0.isStillValid() }
            guard !dead.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                DebugLog.log("pruning \(dead.count) dead window element(s)")
                dead.forEach { self?.removeWindow($0) }
            }
        }
    }

    // MARK: - Snapshot

    /// The visible, ordered switcher list under the current settings.
    public func snapshot() -> [SwitcherItem] {
        resolveFloatingWindows()
        let policy = preferences.windowInclusionPolicy
        let showTabCounts = preferences.showTabCounts
        let activeScreen = NSScreen.main
        return windows.compactMap { window in
            guard window.isActual else { return nil }
            let state = WindowDisplayState(
                isMinimized: window.isMinimized,
                isAppHidden: window.app?.isHidden ?? false,
                // own AX windows are never tracked (own pid is excluded); the only
                // own entry that exists is the registered Settings window
                isOwnWindow: window.isOwnSettingsEntry,
                isOwnSettingsWindow: window.isOwnSettingsEntry,
                isTabbed: window.isTabbed,
                isPictureInPicture: window.isPictureInPicture ?? false,
                isOnCurrentSpace: window.isOnCurrentSpace,
                isOnActiveDisplay: activeScreen.map { window.isOn(screen: $0) } ?? true)
            guard WindowEligibility.shouldDisplay(state, policy: policy) else { return nil }
            return SwitcherItem(id: window.stableId,
                                window: window,
                                title: window.title,
                                appName: window.appName,
                                icon: window.appIcon,
                                tabCount: showTabCounts ? window.tabCount : nil)
        }
    }

    /// Re-evaluates the shared inclusion policy immediately after a user-facing
    /// filter changes. Discovery remains event-driven; no AX work is added.
    public func windowFiltersChanged() {
        guard started else { return }
        onChange?()
    }

    // MARK: - Picture-in-Picture resolution (behavior-based, one query per new window)

    /// Resolves each window's floating status once, lazily, from the window
    /// server (public CGWindowList info — bounds and layer need no capture
    /// permission). Runs only when an unresolved, currently visible window
    /// exists, so idle stays query-free; a window absent from the on-screen
    /// list resolves to "not PiP" (PiP panels join every Space, so a real one
    /// is always on screen).
    private func resolveFloatingWindows() {
        let unresolved = windows.filter {
            $0.isPictureInPicture == nil && !$0.isOwnSettingsEntry
                && !$0.isMinimized && $0.isOnCurrentSpace && $0.ax != nil
        }
        guard !unresolved.isEmpty else { return }
        let onScreen = Self.onScreenWindowFacts()
        // screens in Quartz coordinates, the space CG and AX frames share
        let screens: [CGRect] = NSScreen.screens.compactMap { screen in
            guard let primary = NSScreen.screens.first else { return nil }
            var frame = screen.frame
            frame.origin.y = primary.frame.maxY - screen.frame.maxY
            return frame
        }
        for window in unresolved {
            window.isPictureInPicture = PictureInPictureDetector.isPictureInPicture(
                pid: window.app?.pid ?? -1,
                frame: window.frame,
                onScreenWindows: onScreen,
                screenFrames: screens)
        }
        if unresolved.contains(where: { $0.isPictureInPicture == true }) {
            DebugLog.log("excluding \(unresolved.filter { $0.isPictureInPicture == true }.count) "
                + "Picture-in-Picture window(s)")
        }
    }

    private static func onScreenWindowFacts() -> [PictureInPictureDetector.OnScreenWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return PictureInPictureDetector.OnScreenWindow(
                pid: pid_t(pid),
                frame: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0),
                layer: layer)
        }
    }
}
