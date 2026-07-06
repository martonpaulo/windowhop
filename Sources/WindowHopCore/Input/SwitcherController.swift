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
    private var originWindow: TrackedWindow?
    private var didShowConfirmation = false
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
        PreviewProvider.shared.onPreview = { [weak self] id, image in
            self?.panel.updatePreview(id: id, image: image)
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
        pushEligibleCount()
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

    /// Ends the session cleanly, then opens Settings visible and focused.
    private func openSettingsFromSession() {
        if state.isActive {
            perform(state.escape())
        }
        SettingsWindowController.shared.show()
    }

    private func perform(_ command: SwitcherState.Command) {
        DebugLog.log("perform \(command), phase \(state.phase)")
        switch command {
        case .none:
            break
        case .show(let selectedIndex):
            didShowConfirmation = false
            originWindow = items.first?.window
            panel.show(items: items, selectedIndex: selectedIndex)
            state.updateColumns(panel.columnsPerRow)
            EventTap.shared.mode = sessionTapMode()
            startSessionSupports()
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
        case .activate(let index):
            endSession()
            if index >= 0, index < items.count, let window = items[index].window {
                WindowActions.activate(window)
            }
        case .cancel:
            endSession()
            // the confirmation dialog activated WindowHop; hand focus back to the
            // window that was focused when the session began
            if didShowConfirmation, let originWindow,
               WindowStore.shared.windows.contains(where: { $0 === originWindow }) {
                WindowActions.activate(originWindow)
            }
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
        didShowConfirmation = true
        EventTap.shared.mode = .passthrough
        panel.hide()
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
            panel.presentAgain()
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
        pushEligibleCount()
        guard state.isActive else { return }
        refreshDuringSession()
    }

    private func refreshDuringSession() {
        guard state.isActive else { return }
        let selectedId = state.selectedIndex < items.count ? items[state.selectedIndex].id : nil
        let fresh = WindowStore.shared.snapshot()
        items = items.compactMap { item in fresh.first { $0.id == item.id } }
        let preferredIndex = selectedId.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? state.selectedIndex
        let command = state.listChanged(itemCount: items.count, preferredIndex: preferredIndex)
        if state.isActive {
            panel.update(items: items, selectedIndex: state.selectedIndex)
            state.updateColumns(panel.columnsPerRow)
        }
        if case .cancel = command {
            perform(command)
        }
    }

    private func pushEligibleCount() {
        EventTap.shared.eligibleCount = WindowStore.shared.snapshot().count
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
        panel.hide()
        // previews are session-scoped: pending captures become stale and the
        // in-memory cache is released now
        PreviewProvider.shared.endSession()
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        heldModifierGuard?.invalidate()
        heldModifierGuard = nil
        EventTap.shared.mode = configuredEnabled ? .watching : .off
    }

    private func nsModifier(of flags: CGEventFlags) -> NSEvent.ModifierFlags {
        if flags.contains(.maskAlternate) { return .option }
        if flags.contains(.maskControl) { return .control }
        return .command
    }
}
