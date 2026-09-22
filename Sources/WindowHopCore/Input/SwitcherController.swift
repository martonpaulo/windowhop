import AppKit

/// Orchestrates one switcher session: semantic input events feed the pure
/// SwitcherState; resulting commands drive the panel, window actions, and the
/// close-confirmation dialog. Main thread only.
public final class SwitcherController {
    public static let shared = SwitcherController()

    private var state = SwitcherState()
    /// The session list: seeded at session start and kept in that order while the
    /// switcher is open. Store changes remove or refresh entries in place and append
    /// windows that appeared, but never reorder (see SessionListReconciler).
    private var items: [SwitcherItem] = []
    private let panels = SwitcherPanelGroup()
    private var mouseMonitor: Any?
    private var heldModifierGuard: Timer?
    private var expandedPreview = ExpandedPreviewSession<AnyHashable>()
    private var expandedPreviewTimer: Timer?
    /// Pending reveal of a held session that is still inside its reveal delay.
    private var revealTimer: Timer?
    /// False from session start until the panels are drawn. Before that, panel
    /// and capture work is skipped so a quick tap never draws or announces anything.
    private var isRevealed = false
    private var configuredEnabled = false

    private init() {}

    public func wire() {
        EventTap.shared.onEvent = { [weak self] event in self?.handle(event) }
        WindowStore.shared.onChange = { [weak self] in self?.storeChanged() }
        panels.onItemClicked = { [weak self] index in
            guard let self else { return }
            self.perform(self.state.itemClicked(index: index))
        }
        panels.onItemCloseRequested = { [weak self] index in
            guard let self else { return }
            self.perform(self.state.closeRequested(index: index))
        }
        panels.onSettingsRequested = { [weak self] in
            self?.openSettingsFromSession()
        }
        panels.onPreviewPermissionRequested = { [weak self] in
            self?.openScreenRecordingSettingsFromSession()
        }
        PreviewProvider.shared.onPreview = { [weak self] id, image in
            self?.panels.updatePreview(id: id, image: image)
        }
        PreviewProvider.shared.onPreviewUnavailable = { [weak self] id in
            self?.panels.updatePreviewUnavailable(id: id)
        }
        PreviewProvider.shared.onPermissionRequired = { [weak self] status in
            self?.panels.setPreviewPermissionStatus(status)
        }
        PreviewProvider.shared.onExpandedPreview = { [weak self] id, image in
            self?.deliverExpandedPreview(id: id, image: image)
        }
    }

    /// Applies the enabled/permission state: the tap only exists while the switcher
    /// is both enabled and permitted, so a disabled WindowHop adds zero input latency
    /// and native Cmd-Tab behaves exactly as without WindowHop.
    public func applyConfiguration(enabled: Bool, granted: Bool) {
        EventTap.shared.holdModifier = Preferences.shared.shortcut.holdModifier
        EventTap.shared.persistentShortcut = Preferences.shared.persistentShortcut
        configuredEnabled = enabled && granted
        if configuredEnabled {
            if EventTap.shared.start(), !state.isActive {
                EventTap.shared.mode = .watching
            }
        } else {
            // teardown, not escape: escape belongs to the dialog while confirming,
            // but disabling must release every session resource in every phase
            perform(state.teardown())
            EventTap.shared.stop()
        }
    }

    /// Driven by the Settings shortcut recorder: while it records, the tap passes
    /// every key in `watching`, so pressing an already-active chord reaches the
    /// recorder instead of opening a session.
    public func setShortcutRecordingActive(_ active: Bool) {
        EventTap.shared.isRecordingShortcut = active
    }

    private func handle(_ event: SwitcherInputEvent) {
        switch event {
        case .trigger(let backward):
            let triggerStart = CFAbsoluteTimeGetCurrent()
            items = WindowStore.shared.snapshot()
            perform(state.trigger(backward: backward, itemCount: items.count))
            DebugLog.log("trigger handled: \(items.count) items, phase \(state.phase), "
                + "\(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - triggerStart) * 1000))ms to session start")
            if !state.isActive {
                // the tap flipped to .session optimistically; nothing to show after all
                EventTap.shared.mode = configuredEnabled ? .watching : .off
            }
        case .openPersistent:
            let openStart = CFAbsoluteTimeGetCurrent()
            if !state.isActive {
                items = WindowStore.shared.snapshot()
            }
            perform(state.openPersistent(itemCount: items.count))
            DebugLog.log("persistent open handled: \(items.count) items, phase \(state.phase), "
                + "\(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - openStart) * 1000))ms")
            if !state.isActive {
                EventTap.shared.mode = configuredEnabled ? .watching : .off
            }
        case .step(let backward):
            perform(state.step(backward: backward))
        case .modifierReleased:
            perform(state.modifierReleased())
        case .escape:
            perform(state.escape())
        case .returnKey:
            perform(state.returnKey())
        case .spaceKey:
            perform(state.spaceKey())
        case .arrow(let direction):
            perform(state.arrow(direction))
        case .deleteKey:
            perform(state.deleteKey())
        case .openSettings:
            openSettingsFromSession()
        }
    }

    /// Ends the switcher without committing its target, then opens the global
    /// Settings action. Settings intentionally becomes the next active window;
    /// no preview tile click is allowed to leak through.
    private func openSettingsFromSession() {
        let hadActiveSession = state.isActive
        perform(state.teardown())
        if hadActiveSession {
            WindowActions.afterPendingActions {
                SettingsWindowController.shared.show()
            }
        } else {
            SettingsWindowController.shared.show()
        }
    }

    private func openScreenRecordingSettingsFromSession() {
        perform(state.teardown())
        if ScreenRecordingPermission.status == .notDetermined {
            _ = ScreenRecordingPermission.request()
        } else {
            ScreenRecordingPermission.openSystemSettings()
        }
    }

    private func perform(_ command: SwitcherState.Command) {
        DebugLog.log("perform \(command), phase \(state.phase)")
        switch command {
        case .none:
            break
        case .show:
            // the session exists from here on: input is intercepted and modifier
            // release activates, whether or not the panels are drawn yet
            EventTap.shared.mode = sessionTapMode()
            startSessionSupports()
            // a missed destroy notification once produced a duplicate entry;
            // validate the visible windows in the background and prune the dead
            WindowStore.shared.pruneIfDead(items.compactMap { $0.window?.ax })
            scheduleReveal()
        case .select(let index):
            guard isRevealed else { break }
            panels.select(index)
            targetExpandedPreview(at: index)
        case .activate(let index):
            cancelExpandedPreviewTimer()
            let item = index >= 0 && index < items.count ? items[index] : nil
            let window = item?.window.flatMap { candidate in
                WindowStore.shared.windows.contains(where: { $0 === candidate }) ? candidate : nil
            }
            endSession()
            if let window {
                WindowActions.activate(window)
            }
            expandedPreview.reset()
        case .cancel:
            endSession()
            expandedPreview.reset()
        case .requestClose(let index):
            if index >= 0, index < items.count {
                runCloseConfirmation(for: items[index])
            } else {
                _ = state.confirmationFinished()
            }
        }
    }

    // MARK: - Close confirmation

    /// Closing always requires explicit native confirmation; Cancel is the default.
    /// While the dialog is up the tap consumes nothing, so Return/Escape and a
    /// released Command key go to the dialog instead of the session. The panel is
    /// hidden for the duration so the dialog is unquestionably on top, and is
    /// restored afterwards with the previous selection.
    private func runCloseConfirmation(for item: SwitcherItem) {
        cancelRevealTimer()
        cancelExpandedPreviewTimer()
        expandedPreview.reset()
        panels.hideExpandedPreview()
        EventTap.shared.mode = .passthrough
        panels.hide()
        let sessionID = state.sessionID
        WindowActions.afterPendingActions { [weak self] in
            // a teardown (disable, permission loss) or a newer session may have
            // happened while pending AX actions drained; never revive either
            guard let self, self.state.isConfirming(sessionID: sessionID) else { return }
            self.presentCloseConfirmation(for: item, sessionID: sessionID)
        }
    }

    private func presentCloseConfirmation(for item: SwitcherItem, sessionID: UInt64) {
        let app = item.window?.app
        let isOwnEntry = item.window?.isOwnSettingsEntry ?? false
        let offersQuit = !isOwnEntry && app != nil
        let quitEscalatesToForce = app?.quitRequested ?? false

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close “\(item.title)” in \(item.appName)?"
        alert.informativeText = quitEscalatesToForce
            ? "\(item.appName) was already asked to quit and is still running. Closing the window still uses the normal, safe path."
            : "If the window has unsaved changes, \(item.appName) will ask about them."
        alert.addButton(withTitle: "Cancel")
        let closeButton = alert.addButton(withTitle: "Close Window")
        closeButton.hasDestructiveAction = true
        if offersQuit {
            let quitTitle = quitEscalatesToForce
                ? "Force Quit \(item.appName)…"
                : "Quit \(item.appName)"
            let quitButton = alert.addButton(withTitle: quitTitle)
            quitButton.hasDestructiveAction = true
        }
        NSApp.activate()
        let response = alert.runModal()

        switch response {
        case .alertSecondButtonReturn:
            if let window = item.window,
               WindowStore.shared.windows.contains(where: { $0 === window }) {
                WindowActions.close(window)
            }
        case .alertThirdButtonReturn:
            // the target may have vanished while the dialog was up; then do nothing
            if let app, !app.runningApplication.isTerminated {
                if quitEscalatesToForce {
                    runForceQuitConfirmation(app)
                } else {
                    WindowActions.quit(app)
                }
            }
        default:
            break
        }

        // the user's explicit choice above still ran; restoring the session does not
        // when it was torn down (or replaced) while the dialog was up
        guard state.isConfirming(sessionID: sessionID) else { return }
        _ = state.confirmationFinished()
        if configuredEnabled {
            EventTap.shared.mode = state.isActive ? sessionTapMode() : .watching
        }
        refreshDuringSession()
        if state.isActive {
            if isRevealed {
                panels.presentAgain(presentationMode: .persistent)
            } else {
                // the close was requested before the reveal delay elapsed
                revealPanels()
            }
        }
    }

    /// Force Quit is never the default, never silent, and always a second,
    /// explicitly destructive confirmation after a failed graceful Quit.
    private func runForceQuitConfirmation(_ app: TrackedApp) {
        let name = app.name ?? "the application"
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Force Quit \(name)?"
        alert.informativeText = "\(name) didn't quit when asked. Force quitting ends it immediately and any unsaved changes will be lost."
        alert.addButton(withTitle: "Cancel")
        let forceButton = alert.addButton(withTitle: "Force Quit")
        forceButton.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            WindowActions.forceQuit(app)
        }
    }

    // MARK: - Store changes while the session is open

    private func storeChanged() {
        guard state.isActive else { return }
        refreshDuringSession()
    }

    private func refreshDuringSession() {
        guard state.isActive else { return }
        let selectedId = state.selectedIndex < items.count ? items[state.selectedIndex].id : nil
        let fresh = WindowStore.shared.snapshot()
        let freshById = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sessionById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let preserved = Set(items.lazy
            .filter { freshById[$0.id] == nil && self.shouldPreserveAcrossLocationRefresh($0) }
            .map(\.id))
        let plan = SessionListReconciler.reconcile(sessionIds: items.map(\.id),
                                                   freshIds: fresh.map(\.id),
                                                   preserving: preserved)
        items = plan.ids.compactMap { freshById[$0] ?? sessionById[$0] }
        // a window that appeared mid-session has no capture in flight yet; without
        // this its tile would stay a placeholder for the rest of the session.
        // Before the reveal no capture session exists; revealing captures them all.
        if isRevealed, !plan.appeared.isEmpty {
            DebugLog.log("session list grew by \(plan.appeared.count): now \(items.count) items")
            PreviewProvider.shared.extendSession(
                items: plan.appeared.compactMap { freshById[$0] },
                targetSize: SwitcherPanel.previewContentSize,
                scale: panels.captureScale)
        }
        expandedPreview.retainAvailable(Set(items.map(\.id)))
        let preferredIndex = selectedId.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? state.selectedIndex
        let command = state.listChanged(itemCount: items.count, preferredIndex: preferredIndex)
        if state.isActive, isRevealed {
            panels.update(items: items, selectedIndex: state.selectedIndex)
            state.updateColumns(panels.columnsPerRow)
            targetExpandedPreview(at: state.selectedIndex)
        }
        if case .cancel = command {
            perform(command)
        }
    }

    /// Frozen-session entries may briefly disappear from location metadata while
    /// Spaces update. Preserve only windows that still satisfy every non-location
    /// invariant; the external window is never activated by dwell preview.
    private func shouldPreserveAcrossLocationRefresh(_ item: SwitcherItem) -> Bool {
        guard let window = item.window,
              window.isActual,
              WindowStore.shared.windows.contains(where: { $0 === window }) else { return false }
        let state = WindowDisplayState(
            isMinimized: window.isMinimized,
            isAppHidden: window.app?.isHidden ?? false,
            isOwnWindow: window.isOwnSettingsEntry,
            isOwnSettingsWindow: window.isOwnSettingsEntry,
            isTabbed: window.isTabbed,
            isPictureInPicture: window.isPictureInPicture ?? false,
            // This fallback exists specifically for transient location metadata;
            // all non-location rules still flow through the shared policy.
            isOnCurrentSpace: true,
            isOnActiveDisplay: true)
        return WindowEligibility.shouldDisplay(
            state, policy: Preferences.shared.windowInclusionPolicy)
    }

    // MARK: - Session support

    private func startSessionSupports() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                guard let self else { return }
                self.perform(self.state.outsideClick())
            }
        }
        // fail-safe for missed flagsChanged events (unusual event order, sleep, secure
        // input): while held, verify the modifier is really still down. Session-scoped;
        // never runs while idle, and not at all for persistent sessions.
        guard state.phase == .held, heldModifierGuard == nil else { return }
        heldModifierGuard = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.state.phase == .held else { return }
            let flags = NSEvent.modifierFlags
            if !flags.contains(self.nsModifier(of: EventTap.shared.holdModifier)) {
                self.perform(self.state.modifierReleased())
            }
        }
    }

    /// Resolves this session's target displays and rebuilds the panel set.
    ///
    /// Displays are read live at session start: nothing is cached, and nothing
    /// observes them while WindowHop is idle. A display unplugged between two
    /// sessions is therefore accounted for by the next open, with no invalidation
    /// path to get wrong.
    private func preparePanels(tileCount: Int) {
        let connected = DisplayRegistry.connectedDisplays()
        let targetIDs = Set(PanelDisplayResolver.targets(
            placement: Preferences.shared.switcherDisplayPlacement,
            chosenDisplayID: Preferences.shared.switcherDisplayID,
            available: connected.map(\.descriptor),
            pointerDisplayID: DisplayRegistry.pointerDisplayID()).map(\.id))
        let targets = connected.filter { targetIDs.contains($0.descriptor.id) }
        let metrics = SwitcherTileView.Metrics.metrics(
            for: Preferences.shared.appearanceMode,
            showTabCounts: Preferences.shared.showTabCounts)
        panels.prepare(for: targets, tileCount: tileCount, tileSize: metrics.tileSize)
        DebugLog.log("panels prepared: \(targets.count) display(s), "
            + "placement \(Preferences.shared.switcherDisplayPlacement.rawValue)")
    }

    private func sessionTapMode() -> TapMode {
        state.phase == .held ? .sessionHeld : .sessionSticky
    }

    // MARK: - Reveal

    /// Draws the panels now, or after the held-session reveal delay. Ending the
    /// session first invalidates the timer, so a quick tap activates its target
    /// without the panels ever being ordered front.
    private func scheduleReveal() {
        guard let delay = Preferences.shared.switcherRevealDelay.delay(for: state.phase) else {
            revealPanels()
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.revealPanels()
        }
        revealTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Every presentation step of a session. Uses the selection as it is now,
    /// which includes any stepping done while the reveal was pending.
    private func revealPanels() {
        cancelRevealTimer()
        guard state.phase == .held || state.phase == .sticky, !isRevealed else { return }
        isRevealed = true
        let selectedIndex = state.selectedIndex
        let request = expandedPreview.begin(targetedWindowID: itemID(at: selectedIndex))
        preparePanels(tileCount: items.count)
        panels.show(
            items: items,
            selectedIndex: selectedIndex,
            presentationMode: state.phase == .sticky ? .persistent : .cycling)
        state.updateColumns(panels.columnsPerRow)
        panels.setPreviewPermissionStatus(ScreenRecordingPermission.status)
        scheduleExpandedPreview(request)
        // previews (cached ones already showed instantly) refresh live,
        // asynchronously, never gating panel presentation
        PreviewProvider.shared.beginSession(
            items: items,
            targetSize: SwitcherPanel.previewContentSize,
            scale: panels.captureScale)
    }

    private func cancelRevealTimer() {
        revealTimer?.invalidate()
        revealTimer = nil
    }

    private func endSession() {
        cancelRevealTimer()
        isRevealed = false
        cancelExpandedPreviewTimer()
        panels.hideExpandedPreview()
        panels.hide()
        // views hold images only while presenting them; the provider cache is
        // the only warm owner between sessions (so a closed window or a switch
        // to App Icons, which evicts the cache, leaves no image alive)
        panels.releasePreviewContent()
        // capture is session-scoped: pending results stop delivering live, but
        // the memory-only cache remains warm for the next instant open
        PreviewProvider.shared.endSession()
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        heldModifierGuard?.invalidate()
        heldModifierGuard = nil
        EventTap.shared.mode = configuredEnabled ? .watching : .off
    }

    // MARK: - Non-activating expanded preview

    private func itemID(at index: Int) -> AnyHashable? {
        index >= 0 && index < items.count ? items[index].id : nil
    }

    private func targetExpandedPreview(at index: Int) {
        let id = itemID(at: index)
        // Re-targeting the same window is idempotent: a refresh that preserves
        // the selection must not collapse the presentation or restart dwell.
        guard expandedPreview.targetedWindowID != id else { return }
        cancelExpandedPreviewTimer()
        panels.hideExpandedPreview()
        PreviewProvider.shared.cancelExpandedPreview()
        scheduleExpandedPreview(expandedPreview.target(id))
    }

    /// A capture for the settled dwell target arrived. This is also the path
    /// that opens the presentation when the cache was still empty at dwell.
    private func deliverExpandedPreview(id: AnyHashable, image: NSImage) {
        guard state.isActive, expandedPreview.expandedWindowID == id else { return }
        panels.showExpandedPreview(id: id, image: image)
    }

    private func scheduleExpandedPreview(
        _ request: ExpandedPreviewSession<AnyHashable>.Request?
    ) {
        guard Preferences.shared.appearanceMode == .windowPreviews,
              let request,
              let delay = Preferences.shared.expandedPreviewDelay.duration else { return }
        let timer = Timer(timeInterval: delay,
                          repeats: false) { [weak self] _ in
            self?.presentExpandedPreview(request)
        }
        expandedPreviewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func presentExpandedPreview(
        _ request: ExpandedPreviewSession<AnyHashable>.Request
    ) {
        expandedPreviewTimer = nil
        guard state.isActive,
              let id = expandedPreview.settle(
                request, availableWindowIDs: Set(items.map(\.id))),
              let item = items.first(where: { $0.id == id }),
              item.window != nil else { return }
        if let image = PreviewProvider.shared.cachedPreview(for: id) {
            panels.showExpandedPreview(id: id, image: image)
        }
        PreviewProvider.shared.requestExpandedPreview(
            item: item,
            targetSize: SwitcherPanel.expandedPreviewContentSize,
            scale: panels.captureScale)
    }

    private func cancelExpandedPreviewTimer() {
        expandedPreviewTimer?.invalidate()
        expandedPreviewTimer = nil
    }

    private func nsModifier(of flags: CGEventFlags) -> NSEvent.ModifierFlags {
        if flags.contains(.maskAlternate) { return .option }
        if flags.contains(.maskControl) { return .control }
        return .command
    }
}
