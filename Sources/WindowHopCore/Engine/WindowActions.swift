import AppKit
import ApplicationServices
import WindowHopKit

/// Window actions over public AX APIs only. AltTab uses private SkyLight calls
/// (_SLPSSetFrontProcessWithOptions) here; the public equivalent is to make the
/// window main, raise it, and activate its app. The settable
/// kAXFrontmostAttribute, honored regardless of cooperative-activation rules
/// because the caller holds Accessibility permission, is only a fall-back: it
/// fronts every window of the app on every display (#41).
@MainActor
public enum WindowActions {
    /// Schedules main-thread UI only after every previously requested AX action
    /// has finished. This prevents a committed activation already in flight from
    /// stealing focus back from Settings or a confirmation dialog.
    public static func afterPendingActions(_ action: @escaping @MainActor @Sendable () -> Void) {
        BackgroundWork.axActionsQueue.async {
            DispatchQueue.main.async(execute: action)
        }
    }

    /// Increases with every activation of another app's window; see activate.
    private static var activationGeneration = 0

    public static func activate(
        _ window: TrackedWindow,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        // own Settings window: cooperative NSApp.activate() is sometimes DENIED
        // (macOS 14+ never saw "real" user input reach WindowHop — the tap
        // consumed it), leaving the window ordered but behind. The AX frontmost
        // attribute on our own process is permission-backed and always works —
        // the same mechanism used for every other app.
        if let native = window.nativeWindow {
            NSApp.activate()
            native.makeKeyAndOrderFront(nil)
            native.orderFrontRegardless()
            BackgroundWork.axActionsQueue.async {
                let ownElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
                try? ownElement.setAttribute(kAXFrontmostAttribute, true)
                DispatchQueue.main.async { completion?() }
            }
            return
        }
        guard let ax = window.ax, let app = window.app else {
            completion?()
            return
        }
        // Raise the one window, then activate its app. kAXFrontmostAttribute on the
        // application brings forward every window of the app on every display, so a
        // same-app window on another display jumped in front too (#41, measured with
        // a two-display probe). activate() raises only the main and key windows. It is
        // cooperative and can be refused, so the AX attribute stays as a fall-back
        // when the app did not become frontmost in time.
        // Only the newest activation may fall back: after two quick switches, the
        // first one's check would otherwise pull focus back to its app.
        activationGeneration &+= 1
        let generation = activationGeneration
        let pid = app.runningApplication.processIdentifier
        BackgroundWork.axActionsQueue.async {
            try? ax.setAttribute(kAXMainAttribute, true)
            try? ax.performAction(kAXRaiseAction)
            DispatchQueue.main.async {
                app.runningApplication.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + ActivationFallback.delay) {
                    guard generation == activationGeneration else {
                        completion?()
                        return
                    }
                    BackgroundWork.axActionsQueue.async {
                        if ActivationFallback.isNeeded(
                            focusedPID: focusedApplicationPID(), targetPID: pid)
                        {
                            try? app.axElement.setAttribute(kAXFrontmostAttribute, true)
                        }
                        DispatchQueue.main.async { completion?() }
                    }
                }
            }
        }
    }

    /// The process macOS reports as focused right now, read through the
    /// system-wide AX element (NSWorkspace's cached value lags behind).
    nonisolated private static func focusedApplicationPID() -> pid_t? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(unsafeDowncast(value, to: AXUIElement.self), &pid) == .success else {
            return nil
        }
        return pid
    }

    /// Presses the window's close button, which preserves the target app's native
    /// unsaved-changes workflow. Fullscreen windows are taken out of fullscreen first
    /// (closing is ignored during the fullscreen animation).
    public static func close(_ window: TrackedWindow) {
        if let native = window.nativeWindow {
            native.performClose(nil)
            return
        }
        guard let ax = window.ax else { return }
        // main owns TrackedWindow; the AX actions queue gets the value, not the window
        let isFullscreen = window.isFullscreen
        BackgroundWork.axActionsQueue.async {
            if isFullscreen {
                try? ax.setAttribute(kAXFullscreenAttribute, false)
                BackgroundWork.axActionsQueue.asyncAfter(deadline: .now() + 1) {
                    pressCloseButton(ax)
                }
            } else {
                pressCloseButton(ax)
            }
        }
    }

    /// Graceful termination: the app runs its own unsaved-changes flow. Never
    /// emulated with injected keystrokes.
    public static func quit(_ app: TrackedApp) {
        app.quitRequested = true
        app.runningApplication.terminate()
    }

    /// Immediate termination; only reachable through the explicit, destructive,
    /// twice-confirmed Force Quit path.
    public static func forceQuit(_ app: TrackedApp) {
        app.runningApplication.forceTerminate()
    }

    private nonisolated static func pressCloseButton(_ element: AXUIElement) {
        if let closeButton = (try? element.attributes([kAXCloseButtonAttribute]))?.closeButton {
            try? closeButton.performAction(kAXPressAction)
        } else {
            // the window cannot be closed (no close button, or it vanished)
            DispatchQueue.main.async { NSSound.beep() }
        }
    }
}
