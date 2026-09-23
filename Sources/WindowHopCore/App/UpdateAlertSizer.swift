import AppKit
import WebKit
import WindowHopKit

/// Fits Sparkle's update window to its release notes (#128). Sparkle has no API
/// for the window's size and restores the last one it saved, so the notes opened
/// in a scroll view or with empty space below them.
///
/// Public API only: the window is found by the frame autosave name Sparkle gives
/// it, and the notes by their `WKWebView`. When either is missing (another Sparkle
/// version, no notes), nothing happens and Sparkle's own size stays. The load is
/// observed, never polled, and the observation ends when the window closes.
@MainActor
final class UpdateAlertSizer {
    /// `SUUpdateAlert`'s frame autosave name in Sparkle 2.
    static let windowAutosaveName = "SUUpdateAlert2"

    /// The update page sets no minimum height (`body.is-update`), so the
    /// document is exactly as tall as the notes, margins included.
    private static let contentHeightScript = "document.documentElement.scrollHeight"

    private var loading: NSKeyValueObservation?
    private var closing: (any NSObjectProtocol)?

    /// Called when Sparkle is about to show an update; the window appears on
    /// the next turn of the run loop.
    func fitWhenShown() {
        DispatchQueue.main.async { [weak self] in self?.attach() }
    }

    private func attach() {
        detach()
        guard
            let window = NSApp.windows.first(where: {
                $0.frameAutosaveName == Self.windowAutosaveName
            }),
            let contentView = window.contentView,
            let webView = Self.webView(in: contentView)
        else {
            Log.updates.debug("update window or its notes not found; size left to Sparkle")
            return
        }
        // Every finished load of a web page is measured: the window can appear
        // before its notes start loading, when `isLoading` is false for a blank page.
        loading = webView.observe(\.isLoading, options: [.initial, .new]) {
            [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard !webView.isLoading, webView.url?.scheme?.hasPrefix("http") == true
                else { return }
                self?.measure(webView, in: window)
            }
        }
        closing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.detach() }
        }
    }

    private func detach() {
        loading = nil
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
    }

    private func measure(_ webView: WKWebView, in window: NSWindow) {
        webView.evaluateJavaScript(Self.contentHeightScript) { result, _ in
            MainActor.assumeIsolated {
                guard let height = (result as? NSNumber)?.doubleValue,
                    let screen = window.screen ?? NSScreen.main
                else { return }
                let frame = UpdateAlertSizing.fittedFrame(
                    window: window.frame,
                    notesViewHeight: webView.frame.height,
                    contentHeight: height,
                    minimumHeight: window.minSize.height,
                    visibleScreen: screen.visibleFrame)
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }

    private static func webView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = webView(in: subview) { return found }
        }
        return nil
    }
}
