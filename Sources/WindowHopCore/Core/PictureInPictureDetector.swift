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
/// close button. System PiP (PIPAgent, measured through AVKit) never gets
/// here: it is an AXSystemFloatingWindow, rejected by WindowEligibility.
public enum PictureInPictureDetector {
    /// One on-screen window as the window server reports it (Quartz
    /// coordinates, same space AX frames use).
    public struct OnScreenWindow {
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

    /// `closeButtonEnabled` is the window's AX close button state: `true`
    /// marks an ordinary floating window, `false` or `nil` (no button, or not
    /// read) leaves the layer rule alone in charge.
    public static func isPictureInPicture(pid: pid_t, frame: CGRect?,
                                          closeButtonEnabled: Bool? = nil,
                                          onScreenWindows: [OnScreenWindow],
                                          screenFrames: [CGRect]) -> Bool {
        guard closeButtonEnabled != true, let frame,
              let match = onScreenWindows.first(where: { $0.pid == pid && frameClose($0.frame, frame) }),
              match.layer != 0 else { return false }
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
