import AppKit
import ApplicationServices

/// Window actions over public AX APIs only. AltTab uses private SkyLight calls
/// (_SLPSSetFrontProcessWithOptions) here; the public equivalent is to make the
/// window main, raise it, and make the app frontmost via the settable
/// kAXFrontmostAttribute, which is honored regardless of cooperative-activation
/// rules because the caller holds Accessibility permission.
public enum WindowActions {
    public static func activate(_ window: TrackedWindow) {
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
            }
            return
        }
        guard let ax = window.ax, let app = window.app else { return }
        BackgroundWork.axActionsQueue.async {
            try? ax.setAttribute(kAXMainAttribute, true)
            try? ax.performAction(kAXRaiseAction)
            try? app.axElement.setAttribute(kAXFrontmostAttribute, true)
            DispatchQueue.main.async {
                // reinforcement so menu bar and key state follow; harmless if already front
                app.runningApplication.activate()
            }
        }
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
        BackgroundWork.axActionsQueue.async {
            if window.isFullscreen {
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

    private static func pressCloseButton(_ element: AXUIElement) {
        if let closeButton = (try? element.attributes([kAXCloseButtonAttribute]))?.closeButton {
            try? closeButton.performAction(kAXPressAction)
        } else {
            // the window cannot be closed (no close button, or it vanished)
            DispatchQueue.main.async { NSSound.beep() }
        }
    }
}
