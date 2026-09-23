import CoreGraphics
import Foundation

/// Detects Picture-in-Picture windows by behavior, not by application name:
/// the window server keeps PiP panels floating above normal windows (nonzero
/// window layer), while every regular document window sits at layer 0.
///
/// AX alone cannot tell: a Chromium PiP window reports role AXWindow with
/// subrole AXStandardWindow, exactly like a real browser window (verified
/// against Brave). The floating layer also covers Safari/native PiP (hosted
/// by the system's PIPAgent) without naming any app. Floating windows that
/// cover (almost) a whole screen — Keynote presentations, fullscreen video
/// overlays — are deliberately kept: those are surfaces users switch back to.
///
/// Floating level alone is not PiP: any app may float an ordinary document,
/// palette or dialog window (NSWindow.level). What separates them is the
/// title bar: Chromium PiP (Chrome and Brave, measured for #90) keeps its
/// close, minimize and zoom buttons but disables all three, while AppKit
/// floating document, closable-only and modal-level windows keep an enabled
/// close button. Firefox PiP (and Zen, which is Firefox-based) is the one
/// closable exception: it keeps close and zoom (full screen) enabled and
/// disables only minimize, a combination AeroSpace's AX dump corpus (#115,
/// #117) shows for no ordinary floating window. System PiP (PIPAgent,
/// measured through AVKit) never gets here: it is an AXSystemFloatingWindow, rejected by WindowEligibility.
public enum PictureInPictureDetector {
    /// The enabled state of a window's AX close, minimize and zoom buttons;
    /// `nil` when the window has no such button or it was never read.
    public struct TitleBarButtons: Equatable, Sendable {
        public var close: Bool?
        public var minimize: Bool?
        public var zoom: Bool?

        public init(close: Bool? = nil, minimize: Bool? = nil, zoom: Bool? = nil) {
            self.close = close
            self.minimize = minimize
            self.zoom = zoom
        }

        /// Firefox PiP's title bar: closable and zoomable, but not minimizable.
        var isFirefoxPictureInPicture: Bool {
            close == true && minimize == false && zoom == true
        }

        /// An enabled close button marks an ordinary floating window, except
        /// for the Firefox PiP combination.
        var provesOrdinaryWindow: Bool {
            close == true && !isFirefoxPictureInPicture
        }
    }

    /// One on-screen window as the window server reports it (Quartz
    /// coordinates, same space AX frames use).
    public struct OnScreenWindow: Sendable {
        public let pid: pid_t
        public let frame: CGRect
        public let layer: Int

        public init(pid: pid_t, frame: CGRect, layer: Int) {
            self.pid = pid
            self.frame = frame
            self.layer = layer
        }
    }

    /// Fraction of a screen a floating window must cover to count as a
    /// fullscreen surface rather than a PiP panel.
    static let fullscreenCoverage: CGFloat = 0.85

    /// The layer AppKit gives app-modal alerts and open/save panels. They have
    /// no close button at all, so the button fact cannot rescue them; no PiP
    /// panel floats here (layer 3 for Chromium and Firefox PiP, 19 for PIPAgent).
    /// Found through AeroSpace's AX dump corpus (#115) and measured on macOS 26:
    /// `NSAlert` and `NSOpenPanel` under `runModal()` both sit at layer 8.
    static let modalPanelLayer = Int(CGWindowLevelForKey(.modalPanelWindow))

    /// `buttons` is the window's AX title-bar button state: an enabled close
    /// button marks an ordinary floating window unless minimize is disabled
    /// while zoom stays enabled (Firefox PiP); a disabled or missing close
    /// button, or an unread one, leaves the layer rule alone in charge.
    public static func isPictureInPicture(pid: pid_t, frame: CGRect?,
                                          buttons: TitleBarButtons = TitleBarButtons(),
                                          onScreenWindows: [OnScreenWindow],
                                          screenFrames: [CGRect]) -> Bool {
        guard !buttons.provesOrdinaryWindow, let frame,
              let match = onScreenWindows.first(where: { $0.pid == pid && frameClose($0.frame, frame) }),
              match.layer != 0, match.layer != modalPanelLayer else { return false }
        let coversAScreen = screenFrames.contains { screen in
            let overlap = frame.intersection(screen)
            return screen.width > 0 && screen.height > 0
                && overlap.width * overlap.height >= screen.width * screen.height * fullscreenCoverage
        }
        return !coversAScreen
    }

    /// Same tolerance the preview matcher uses for AX ↔ window-server frames.
    private static func frameClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 5 && abs(a.origin.y - b.origin.y) < 5
            && abs(a.width - b.width) < 5 && abs(a.height - b.height) < 5
    }
}
