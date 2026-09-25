import AppKit
import ApplicationServices
import WindowHopKit

/// A window entry as consumed by the switcher UI: plain values plus a reference
/// for actions (activate/close). `id` is the stable identity used to match entries
/// across snapshots while the switcher is open.
public struct SwitcherItem {
    public let id: AnyHashable
    public let window: TrackedWindow?
    /// The raw window title: preview matching and AX association use this.
    public let title: String
    /// What the tile shows and speaks: the title, qualified by CollisionLabel when
    /// same-app entries would otherwise share it.
    public let displayTitle: String
    public let appName: String
    public let icon: NSImage?
    public let tabCount: Int?

    public init(
        id: AnyHashable, window: TrackedWindow?, title: String,
        displayTitle: String? = nil,
        appName: String, icon: NSImage?, tabCount: Int?
    ) {
        self.id = id
        self.window = window
        self.title = title
        self.displayTitle = displayTitle ?? title
        self.appName = appName
        self.icon = icon
        self.tabCount = tabCount
    }
}

/// Main-thread source of truth: every tracked app and window, in window-level MRU order
/// (index 0 = currently focused window). Event-driven only — AX notifications,
/// NSWorkspace notifications, and KVO; nothing polls.
@MainActor
public final class WindowStore {
    public private(set) var apps: [pid_t: TrackedApp] = [:]
    /// MRU order: index 0 is the focused window. Derived from `order`, the one
    /// owner of ordering policy (Core/MRUOrder), so its tests cover production.
    public var windows: [TrackedWindow] { order.ids.compactMap { windowsById[$0] } }
    private var order = MRUOrder<UUID>()
    private var windowsById: [UUID: TrackedWindow] = [:]
    /// Fired on any change that can affect the visible list.
    public var onChange: (() -> Void)?

    private let preferences: Preferences
    /// Evicts a removed window's preview (see `discardPreviews`).
    private let previews: PreviewProvider
    /// Carried by every app's AXObserver; holds this store weakly.
    private(set) lazy var router = AXNotificationRouter(store: self)
    private var runningAppsObserver: NSKeyValueObservation?
    private var started = false
    /// Lock, session and sleep state (#38): whether AX answers can be trusted right now.
    private var sessionMonitor: SessionMonitor?
    private var session: SessionAvailability { sessionMonitor?.availability ?? SessionAvailability() }

    /// Owned by `AppDelegate`; tests and the debug harness build their own.
    public init(preferences: Preferences, previews: PreviewProvider) {
        self.preferences = preferences
        self.previews = previews
    }

    /// Requires Accessibility permission. Safe to call again after stop().
    public func start() {
        guard !started else { return }
        started = true
        AXUIElement.setGlobalTimeout()
        runningAppsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) {
            [weak self] _, change in
            DispatchQueue.main.async { [weak self] in
                for app in change.newValue ?? [] { self?.addApp(app) }
                for app in change.oldValue ?? [] { self?.removeApp(app) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // trace only: display changes are correlated with inventory changes (#38)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        sessionMonitor = SessionMonitor { [weak self] event, needsRecovery in
            self?.sessionEvent(event, needsRecovery: needsRecovery)
        }
        for app in NSWorkspace.shared.runningApplications { addApp(app) }
    }

    public func stop() {
        guard started else { return }
        started = false
        runningAppsObserver = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        sessionMonitor?.stop()
        sessionMonitor = nil
        for app in apps.values { app.stopObserving() }
        apps = [:]
        discardPreviews(of: windows)
        order = MRUOrder()
        windowsById = [:]
        onChange?()
    }

    // MARK: - App lifecycle

    private func addApp(_ runningApplication: NSRunningApplication) {
        let pid = runningApplication.processIdentifier
        guard started, pid != ProcessInfo.processInfo.processIdentifier, pid > 0,
            apps[pid] == nil, !runningApplication.isTerminated
        else { return }
        apps[pid] = TrackedApp(runningApplication, router: router)
    }

    private func removeApp(_ departedApplication: NSRunningApplication) {
        // Its PID may already be -1 after the KVO hop; isEqual also guards against PID reuse.
        let app =
            apps[departedApplication.processIdentifier].flatMap {
                $0.runningApplication.isEqual(departedApplication) ? $0 : nil
            } ?? apps.values.first { $0.runningApplication.isEqual(departedApplication) }
        // NSWorkspace's old KVO value is the removal signal; do not gate it on isTerminated.
        guard let app else { return }
        let pid = app.pid
        app.stopObserving()
        apps[pid] = nil
        let removed = windows.filter { $0.app === app }
        removed.forEach(forget)
        Log.windows.debug("remove: app \(pid, privacy: .public) quit, \(removed.count, privacy: .public) window(s)")
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
    func discoverWindows(of observer: AppObserver) {
        // a request that outlived the app's removal (or a pid reused by a new app) is stale
        guard started, let app = apps[observer.pid], app.observer === observer else { return }
        let element = app.axElement
        let pid = app.pid
        let router = router
        BackgroundWork.axReadsQueue.async {
            guard let elements = element.windowElements().listedWindows else { return }
            for windowElement in elements {
                router.routeWindowEvent(kAXWindowCreatedNotification, windowElement, pid)
            }
            // seed MRU: the frontmost app's focused window belongs at the front
            if app.runningApplication.isActive,
                let focused = (try? element.attributes([kAXFocusedWindowAttribute]))?.focusedWindow
            {
                router.routeWindowEvent(kAXFocusedWindowChangedNotification, focused, pid)
            }
        }
    }

    func windowEvent(
        _ notification: String, element: AXUIElement, pid: pid_t,
        attributes: AXAttributes, tabs: TabObservation
    ) {
        guard started, let app = apps[pid] else { return }
        let existing = windows.first { $0.ax == element }
        let isFocusEvent =
            notification == kAXFocusedWindowChangedNotification
            || notification == kAXMainWindowChangedNotification
        let window: TrackedWindow
        if let existing {
            existing.update(from: attributes, tabs: tabs)
            window = existing
        } else {
            let facts = app.windowFacts(from: attributes)
            // unknown non-windows (menus, tooltips, …) are ignored entirely, but a window
            // that just got focused is real even if its subrole looks wrong mid-animation
            guard WindowEligibility.isActualWindow(facts) || isFocusEvent else { return }
            window = TrackedWindow(ax: element, app: app, attributes: attributes, tabs: tabs)
            windowsById[window.stableId] = window
            order.add(window.stableId)
            app.observer.enqueueWindowSubscription(element)
        }
        let tabsBefore = (isTabbed: window.isTabbed, groupCount: window.tabGroupIds?.count)
        updateTabGroup(for: window, tabs: tabs, isFocusEvent: isFocusEvent)
        if existing == nil {
            // an active tab discovered earlier may be waiting for this window
            let sameApp = windows.filter { $0.app === app && $0 !== window }
            applyTabStates(
                TabGroupResolver.resolveArrival(
                    newWindow: tabDescriptor(window),
                    sameAppWindows: sameApp.map(tabDescriptor)))
        }
        traceTabEvent(notification, window: window, tabs: tabs, before: tabsBefore)
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
        guard windowsById[window.stableId] != nil else { return }
        order.focused(window.stableId)
    }

    /// Drops a window from the MRU order; callers own preview eviction and onChange.
    private func forget(_ window: TrackedWindow) {
        order.remove(window.stableId)
        windowsById[window.stableId] = nil
    }

    /// A `kAXUIElementDestroyed` notification. While the session cannot report windows
    /// it proves nothing (#38): the recovery re-enumeration and its liveness probe remove
    /// the window later if it really is gone.
    func windowDestroyed(_ element: AXUIElement) {
        guard SpaceMembership.acceptsDestroyNotification(session: session) else {
            if let window = windows.first(where: { $0.ax == element }) {
                Log.windows.debug(
                    "remove: destroyed \(Self.traceId(window), privacy: .public) ignored, session unavailable")
            }
            return
        }
        removeWindow(element, reason: "destroyed")
    }

    private func removeWindow(_ element: AXUIElement, reason: StaticString) {
        guard let removed = windows.first(where: { $0.ax == element }) else { return }
        Log.windows.debug("remove: \(reason, privacy: .public) \(Self.traceId(removed), privacy: .public)")
        forget(removed)
        discardPreviews(of: [removed])
        if let groupIds = removed.tabGroupIds {
            Log.windows.debug(
                """
                tabs: removed \(Self.traceId(removed), privacy: .public) \
                group \(groupIds.count, privacy: .public)
                """)
            let remaining = windows.filter { $0.app === removed.app }
            applyTabStates(
                TabGroupResolver.resolveRemoval(
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
        windowsById[entry.stableId] = entry
        // an unknown item focused enters at the front: Settings opens focused
        order.focused(entry.stableId)
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(ownWindowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        center.addObserver(
            self, selector: #selector(ownWindowMiniaturizedChanged(_:)),
            name: NSWindow.didMiniaturizeNotification, object: window)
        center.addObserver(
            self, selector: #selector(ownWindowMiniaturizedChanged(_:)),
            name: NSWindow.didDeminiaturizeNotification, object: window)
        center.addObserver(
            self, selector: #selector(ownWindowFocused(_:)),
            name: NSWindow.didBecomeKeyNotification, object: window)
        // Dragging Settings to another display can change whether it belongs in
        // an open session's list. The frame itself is read live on snapshot;
        // these only say "look again". Scoped to this one window, removed with
        // the rest on close, and they never poll.
        center.addObserver(
            self, selector: #selector(ownWindowGeometryChanged(_:)),
            name: NSWindow.didMoveNotification, object: window)
        center.addObserver(
            self, selector: #selector(ownWindowGeometryChanged(_:)),
            name: NSWindow.didResizeNotification, object: window)
        onChange?()
    }

    /// The one removal-to-retention handoff. Every path that drops a window
    /// goes through it, so a removed stable id can never outlive its window in
    /// the preview cache — reopening Settings mints a fresh id each time, and
    /// the old ones would otherwise survive until the appearance changed.
    private func discardPreviews(of removed: [TrackedWindow]) {
        for window in removed { previews.evict(window.stableId) }
    }

    private func ownEntry(for window: NSWindow) -> TrackedWindow? {
        windows.first { $0.isOwnSettingsEntry && $0.nativeWindow === window }
    }

    @objc private func ownWindowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let entry = ownEntry(for: window)
        else { return }
        NotificationCenter.default.removeObserver(self, name: nil, object: window)
        forget(entry)
        discardPreviews(of: [entry])
        onChange?()
    }

    @objc private func ownWindowMiniaturizedChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let entry = ownEntry(for: window)
        else { return }
        entry.isMinimized = notification.name == NSWindow.didMiniaturizeNotification
        onChange?()
    }

    @objc private func ownWindowGeometryChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            ownEntry(for: window) != nil
        else { return }
        onChange?()
    }

    @objc private func ownWindowFocused(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let entry = ownEntry(for: window)
        else { return }
        windowFocused(entry)
        onChange?()
    }

    // MARK: - Tab groups (tabs are never independent entries)

    private func tabDescriptor(_ window: TrackedWindow)
        -> TabGroupResolver.WindowDescriptor<UUID>
    {
        TabGroupResolver.WindowDescriptor(
            id: window.stableId,
            title: window.title,
            isTabbed: window.isTabbed,
            groupIds: window.tabGroupIds,
            frame: window.frame,
            reportedTabTitles: window.reportedTabTitles)
    }

    private func updateTabGroup(for window: TrackedWindow, tabs: TabObservation, isFocusEvent: Bool) {
        // cheap fast path: an incomplete read changes nothing, and a window with no
        // tab bar and no group membership has nothing to maintain
        switch tabs {
        case .unknown: return
        case .standalone: guard window.tabGroupIds != nil else { return }
        case .group: break
        }
        let sameApp = windows.filter { $0.app === window.app && $0 !== window }
        applyTabStates(
            TabGroupResolver.resolve(
                active: tabDescriptor(window),
                observation: tabs,
                sameAppWindows: sameApp.map(tabDescriptor),
                isFocusEvent: isFocusEvent))
    }

    private func applyTabStates(_ changes: [UUID: TabGroupResolver.WindowTabState<UUID>]) {
        guard !changes.isEmpty else { return }
        for window in windows {
            if let change = changes[window.stableId] {
                Log.windows.debug(
                    """
                    tabs: change \(Self.traceId(window), privacy: .public) \
                    tabbed \(window.isTabbed, privacy: .public)->\(change.isTabbed, privacy: .public) \
                    group \(window.tabGroupIds?.count ?? 0, privacy: .public)->\
                    \(change.groupIds?.count ?? 0, privacy: .public)
                    """)
                window.isTabbed = change.isTabbed
                window.tabGroupIds = change.groupIds
            }
        }
    }

    /// Title-free debug tab trace (#82): only windows with a tab bar or
    /// a recorded group are logged. `frameEqualsGroup` compares the window's frame with
    /// its group's active member, rounded like TabGroupResolver does.
    private func traceTabEvent(
        _ notification: String, window: TrackedWindow, tabs: TabObservation,
        before: (isTabbed: Bool, groupCount: Int?)
    ) {
        guard Log.isWindowsDebugEnabled else { return }
        let observation: String
        switch tabs {
        case .unknown: observation = "unknown"
        case .standalone: observation = "standalone"
        case .group(let titles): observation = "group(\(titles.count))"
        }
        guard before.groupCount != nil || window.tabGroupIds != nil || observation.hasPrefix("group")
        else { return }
        let activeMember = windows.first {
            window.tabGroupIds?.contains($0.stableId) == true && !$0.isTabbed && $0 !== window
        }
        let frameEqualsGroup =
            activeMember.map { member -> String in
                guard let a = member.frame?.integral, let b = window.frame?.integral else { return "?" }
                return a == b ? "yes" : "no"
            } ?? "-"
        let hiddenTabs = windows.filter { $0.app === window.app && $0.isTabbed }.count
        Log.windows.debug(
            """
            tabs: \(notification, privacy: .public) \(Self.traceId(window), privacy: .public) \
            \(observation, privacy: .public) \
            tabbed \(before.isTabbed, privacy: .public)->\(window.isTabbed, privacy: .public) \
            group \(before.groupCount ?? 0, privacy: .public)->\
            \(window.tabGroupIds?.count ?? 0, privacy: .public) \
            frameEqualsGroup \(frameEqualsGroup, privacy: .public) appHiddenTabs \(hiddenTabs, privacy: .public)
            """)
    }

    private static func traceId(_ window: TrackedWindow) -> String {
        String(window.stableId.uuidString.prefix(8))
    }

    @objc private func activeSpaceChanged() {
        refreshInventory(reason: "space changed")
    }

    @objc private func screenParametersChanged() {
        Log.windows.debug("lifecycle: screen parameters changed, \(NSScreen.screens.count, privacy: .public) screen(s)")
    }

    private func sessionEvent(_ event: SessionAvailability.Event, needsRecovery: Bool) {
        Log.windows.debug(
            """
            lifecycle: \(event.rawValue, privacy: .public), \
            session \(self.session.isUsable ? "usable" : "unavailable", privacy: .public)
            """)
        // one event-driven pass: what was read in the dark was never applied
        if needsRecovery { refreshInventory(reason: "recovery after \(event.rawValue)") }
    }

    /// Re-enumerates every app: discovers windows we could not see before (other-Space
    /// windows enter kAXWindows once their Space is visited) and updates each window's
    /// current-Space flag. Runs on Space changes and once when the session becomes usable
    /// again after a lock, a session switch or a sleep (#38). Asks nothing while the
    /// session cannot report windows: the recovery pass follows.
    func refreshInventory(reason: String) {
        guard started else { return }
        let session = self.session
        guard session.isUsable else {
            Log.windows.debug("inventory: \(reason, privacy: .public) skipped, session unavailable")
            return
        }
        let readEpoch = session.epoch
        let appsSnapshot = Array(apps.values)
        let router = router
        Log.windows.debug(
            """
            inventory: \(reason, privacy: .public), \(appsSnapshot.count, privacy: .public) app(s), \
            \(self.windows.count, privacy: .public) tracked window(s)
            """)
        BackgroundWork.axReadsQueue.async { [weak self] in
            for app in appsSnapshot {
                let enumeration = app.axElement.windowElements()
                for windowElement in enumeration.listedWindows ?? [] {
                    router.routeWindowEvent(kAXWindowCreatedNotification, windowElement, app.pid)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.applyEnumeration(enumeration, of: app, readEpoch: readEpoch)
                }
            }
        }
    }

    private func applyEnumeration(
        _ enumeration: WindowEnumeration<AXUIElement>, of app: TrackedApp,
        readEpoch: UInt64
    ) {
        let appWindows = windows.filter { $0.app === app }
        // a failed read, or one taken while the session could not report windows, keeps
        // each window's last known Space flag; see SpaceMembership for why an empty
        // success still updates it
        let reconciliation = SpaceMembership.reconcile(
            tracked: appWindows.compactMap(\.ax), enumeration: enumeration,
            session: session, readEpoch: readEpoch)
        var flippedOff = 0
        for window in appWindows {
            guard let ax = window.ax, let isCurrent = reconciliation.currentSpace[ax] else { continue }
            if window.isOnCurrentSpace && !isCurrent { flippedOff += 1 }
            window.isOnCurrentSpace = isCurrent
        }
        if !appWindows.isEmpty {
            Log.windows.debug(
                """
                inventory: app \(app.pid, privacy: .public) \(Self.traceKind(enumeration), privacy: .public) \
                trusted \(self.session.trusts(readStartedAt: readEpoch), privacy: .public) \
                tracked \(appWindows.count, privacy: .public) \
                offSpace+\(flippedOff, privacy: .public) suspects \(reconciliation.suspects.count, privacy: .public)
                """)
        }
        onChange?()
        // a window absent from kAXWindows is either on another Space (keep it) or
        // silently dead — a missed destroy notification once produced duplicate
        // entries. Validate and prune.
        pruneIfDead(reconciliation.suspects)
    }

    private static func traceKind(_ enumeration: WindowEnumeration<AXUIElement>) -> String {
        switch enumeration {
        case .listed(let windows): "listed(\(windows.count))"
        case .unavailable: "unavailable"
        case .applicationInvalid: "applicationInvalid"
        }
    }

    /// Validates possibly-stale AX elements off the main thread and removes the
    /// dead ones. Cheap (one attribute read per suspect) and strictly event-driven.
    /// A probe taken while the session cannot report windows proves nothing (#38).
    func pruneIfDead(_ elements: [AXUIElement]) {
        guard !elements.isEmpty else { return }
        guard session.isUsable else {
            Log.windows.debug("prune: \(elements.count, privacy: .public) suspect(s) skipped, session unavailable")
            return
        }
        let readEpoch = session.epoch
        BackgroundWork.axReadsQueue.async { [weak self] in
            let dead = elements.filter { !$0.isStillValid() }
            guard !dead.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let confirmed = SpaceMembership.confirmedDead(dead, session: self.session, readEpoch: readEpoch)
                Log.windows.debug(
                    """
                    prune: \(elements.count, privacy: .public) suspect(s), \(dead.count, privacy: .public) dead, \
                    \(confirmed.count, privacy: .public) removed
                    """)
                for element in confirmed { self.removeWindow(element, reason: "pruned") }
            }
        }
    }

    /// Session-start re-read of tab bars (#113). A live Window ▸ Merge All Windows
    /// sends no observed AX notification, so merged windows would stay separate
    /// entries until an unrelated event. Called once per session open, never while
    /// idle; reads only the entries `TabGroupResolver.sessionRereadTargets` picks,
    /// on the AX reads queue, and applies them in one main-thread pass.
    public func rereadTabGroups(of items: [SwitcherItem]) {
        let windows = items.compactMap(\.window)
        let targetIds = Set(
            TabGroupResolver.sessionRereadTargets(
                windows.map { (id: $0.stableId, appId: $0.app.map(ObjectIdentifier.init)) }))
        let targets = windows.compactMap { window -> (UUID, AXUIElement)? in
            guard targetIds.contains(window.stableId), let ax = window.ax else { return nil }
            return (window.stableId, ax)
        }
        guard !targets.isEmpty else { return }
        let keys = AXNotificationRouter.windowAttributeKeys + [kAXChildrenAttribute]
        BackgroundWork.axReadsQueue.async { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let reads = targets.compactMap { id, element -> (UUID, AXUIElement, AXAttributes, TabObservation)? in
                guard let attributes = try? element.attributes(keys) else { return nil }
                return (id, element, attributes, AXUIElement.tabObservation(fromWindow: attributes))
            }
            let rereadMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Log.windows.debug(
                """
                tab re-read: \(reads.count, privacy: .public)/\(targets.count, privacy: .public) \
                window(s) in \(rereadMs, format: .fixed(precision: 2), privacy: .public)ms
                """)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, !reads.isEmpty else { return }
                for (id, element, attributes, tabs) in reads {
                    guard let window = self.windowsById[id], window.ax == element else { continue }
                    window.update(from: attributes, tabs: tabs)
                    // a session-open re-read is not focus evidence (#82 rule 2)
                    self.updateTabGroup(for: window, tabs: tabs, isFocusEvent: false)
                }
                self.onChange?()
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
        let tracked = windows
        var excluded = [WindowEligibility.ExclusionReason: Int]()
        let visible = tracked.filter { window in
            guard window.isActual else { return false }
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
            guard let reason = WindowEligibility.exclusionReason(state, policy: policy) else { return true }
            excluded[reason, default: 0] += 1
            return false
        }
        traceSnapshot(tracked: tracked.count, eligible: visible.count, excluded: excluded)
        // collisions are judged among the entries actually shown
        let labels = CollisionLabel.labels(
            for: visible.map { window in
                CollisionLabel.Entry(
                    appId: window.app.map(ObjectIdentifier.init),
                    title: window.title,
                    documentPath: window.documentPath)
            })
        return zip(visible, labels).map { window, label in
            SwitcherItem(
                id: window.stableId,
                window: window,
                title: window.title,
                displayTitle: label,
                appName: window.appName,
                icon: window.appIcon,
                tabCount: showTabCounts ? window.tabCount : nil)
        }
    }

    /// Title-free snapshot trace (#38): how many windows are tracked, shown, and kept
    /// out by each eligibility rule.
    private func traceSnapshot(
        tracked: Int, eligible: Int,
        excluded: [WindowEligibility.ExclusionReason: Int]
    ) {
        guard Log.isWindowsDebugEnabled else { return }
        let reasons = WindowEligibility.ExclusionReason.allCases
            .compactMap { reason in excluded[reason].map { "\(reason.rawValue) \($0)" } }
            .joined(separator: ", ")
        Log.windows.debug(
            """
            snapshot: tracked \(tracked, privacy: .public), eligible \(eligible, privacy: .public), \
            excluded [\(reasons, privacy: .public)]
            """)
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
                buttons: window.titleBarButtons,
                onScreenWindows: onScreen,
                screenFrames: screens)
        }
        if unresolved.contains(where: { $0.isPictureInPicture == true }) {
            let pipCount = unresolved.filter { $0.isPictureInPicture == true }.count
            Log.windows.debug("excluding \(pipCount, privacy: .public) Picture-in-Picture window(s)")
        }
    }

    private static func onScreenWindowFacts() -> [PictureInPictureDetector.OnScreenWindow] {
        guard
            let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return info.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            return PictureInPictureDetector.OnScreenWindow(
                pid: pid_t(pid),
                frame: CGRect(
                    x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0),
                layer: layer)
        }
    }
}
