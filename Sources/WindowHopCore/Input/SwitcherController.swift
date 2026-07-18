import AppKit

/// Orchestrates one switcher session: semantic input events feed the pure
/// SwitcherState; resulting commands drive the panel, window actions, and the
/// close-confirmation dialog. Main thread only.
public final class SwitcherController {
    public static let shared = SwitcherController()

    private var state = SwitcherState()
    /// Snapshot frozen at session start: stable ordering while the switcher is open.
    /// Store changes remove or refresh entries but never reorder or add.
    private var items: [SwitcherItem] = []
    private let panel = SwitcherPanel()
    private var mouseMonitor: Any?
    private var heldModifierGuard: Timer?
    private var expandedPreview = ExpandedPreviewSession<AnyHashable>()
    private var expandedPreviewTimer: Timer?
    private var configuredEnabled = false

    private init() {}

    public func wire() {
        EventTap.shared.onEvent = { [weak self] event in self?.handle(event) }
        WindowStore.shared.onChange = { [weak self] in self?.storeChanged() }
        panel.onItemClicked = { [weak self] index in
            guard let self else { return }
            self.perform(self.state.itemClicked(index: index))
        }
        panel.onItemCloseRequested = { [weak self] index in
            guard let self else { return }
            self.perform(self.state.closeRequested(index: index))
        }
        panel.onSettingsRequested = { [weak self] in
            self?.openSettingsFromSession()
        }
        panel.onPreviewPermissionRequested = { [weak self] in
            self?.openScreenRecordingSettingsFromSession()
        }
        PreviewProvider.shared.onPreview = { [weak self] id, image in
            self?.panel.updatePreview(id: id, image: image)
        }
        PreviewProvider.shared.onPreviewUnavailable = { [weak self] id in
            self?.panel.updatePreviewUnavailable(id: id)
        }
        PreviewProvider.shared.onPermissionRequired = { [weak self] status in
            self?.panel.setPreviewPermissionStatus(status)
        }
        PreviewProvider.shared.onExpandedPreview = { [weak self] id, image in
            self?.panel.updateExpandedPreview(id: id, image: image)
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
            if state.isActive {
                perform(state.escape())
            }
            state.reset()
            EventTap.shared.stop()
        }
    }

    private func handle(_ event: SwitcherInputEvent) {
        switch event {
        case .trigger(let backward):
            let triggerStart = CFAbsoluteTimeGetCurrent()
            items = WindowStore.shared.snapshot()
            perform(state.trigger(backward: backward, itemCount: items.count))
            DebugLog.log("trigger handled: \(items.count) items, phase \(state.phase), "
                + "\(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - triggerStart) * 1000))ms to visible panel")
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
        if hadActiveSession {
            state.reset()
            endSession()
            expandedPreview.reset()
        }
        if hadActiveSession {
            WindowActions.afterPendingActions {
                SettingsWindowController.shared.show()
            }
        } else {
            SettingsWindowController.shared.show()
        }
    }

    private func openScreenRecordingSettingsFromSession() {
        let hadActiveSession = state.isActive
        if hadActiveSession {
            state.reset()
            endSession()
            expandedPreview.reset()
        }
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
        case .show(let selectedIndex):
            let request = expandedPreview.begin(targetedWindowID: itemID(at: selectedIndex))
            panel.show(
                items: items,
                selectedIndex: selectedIndex,
                presentationMode: state.phase == .sticky ? .persistent : .cycling)
            state.updateColumns(panel.columnsPerRow)
            EventTap.shared.mode = sessionTapMode()
            startSessionSupports()
            panel.setPreviewPermissionStatus(ScreenRecordingPermission.status)
            scheduleExpandedPreview(request)
            // previews (cached ones already showed instantly) refresh live,
            // asynchronously, never gating panel presentation
            PreviewProvider.shared.beginSession(
                items: items,
                targetSize: SwitcherPanel.previewContentSize,
                scale: NSScreen.main?.backingScaleFactor ?? 2)
            // a missed destroy notification once produced a duplicate entry;
            // validate the visible windows in the background and prune the dead
            WindowStore.shared.pruneIfDead(items.compactMap { $0.window?.ax })
        case .select(let index):
            panel.select(index)
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
        cancelExpandedPreviewTimer()
        expandedPreview.reset()
        panel.hideExpandedPreview()
        EventTap.shared.mode = .passthrough
        panel.hide()
        WindowActions.afterPendingActions { [weak self] in
            guard let self, self.state.phase == .confirming else { return }
            self.presentCloseConfirmation(for: item)
        }
    }

    private func presentCloseConfirmation(for item: SwitcherItem) {
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

        _ = state.confirmationFinished()
        if configuredEnabled {
            EventTap.shared.mode = state.isActive ? sessionTapMode() : .watching
        }
        refreshDuringSession()
        if state.isActive {
            panel.presentAgain(presentationMode: .persistent)
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
        items = items.compactMap { item in
            fresh.first { $0.id == item.id } ?? (shouldPreserveAcrossLocationRefresh(item)
                ? item
                : nil)
        }
        expandedPreview.retainAvailable(Set(items.map(\.id)))
        let preferredIndex = selectedId.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? state.selectedIndex
        let command = state.listChanged(itemCount: items.count, preferredIndex: preferredIndex)
        if state.isActive {
            panel.update(items: items, selectedIndex: state.selectedIndex)
            state.updateColumns(panel.columnsPerRow)
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

    private func sessionTapMode() -> TapMode {
        state.phase == .held ? .sessionHeld : .sessionSticky
    }

    private func endSession() {
        cancelExpandedPreviewTimer()
        panel.hideExpandedPreview()
        panel.hide()
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
        cancelExpandedPreviewTimer()
        panel.hideExpandedPreview()
        PreviewProvider.shared.cancelExpandedPreview()
        scheduleExpandedPreview(expandedPreview.target(itemID(at: index)))
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
            panel.showExpandedPreview(id: id, image: image)
        }
        PreviewProvider.shared.requestExpandedPreview(
            item: item,
            targetSize: SwitcherPanel.expandedPreviewContentSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2)
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
