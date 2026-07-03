import AppKit
import ApplicationServices

/// Window actions over public AX APIs only. AltTab uses private SkyLight calls
/// (_SLPSSetFrontProcessWithOptions) here; the public equivalent is to make the
/// window main, raise it, and make the app frontmost via the settable
/// kAXFrontmostAttribute, which is honored regardless of cooperative-activation
/// rules because the caller holds Accessibility permission.
public enum WindowActions {
    public static func activate(_ window: TrackedWindow) {
        let app = window.app
        BackgroundWork.axActionsQueue.async {
            try? window.ax.setAttribute(kAXMainAttribute, true)
            try? window.ax.performAction(kAXRaiseAction)
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
        BackgroundWork.axActionsQueue.async {
            if window.isFullscreen {
                try? window.ax.setAttribute(kAXFullscreenAttribute, false)
                BackgroundWork.axActionsQueue.asyncAfter(deadline: .now() + 1) {
                    pressCloseButton(window.ax)
                }
            } else {
                pressCloseButton(window.ax)
            }
        }
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
