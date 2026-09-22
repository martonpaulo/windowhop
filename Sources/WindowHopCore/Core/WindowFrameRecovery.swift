import CoreGraphics
import Foundation

/// Keeps a restored window reachable. A saved frame can point at a display
/// that is no longer connected (or at a region a resolution change removed);
/// AppKit restores it there anyway, leaving the window invisible. The rule:
/// a frame whose title bar can still be grabbed stays where the person put it,
/// anything else moves onto the main display.
public enum WindowFrameRecovery {
    /// - Parameters:
    ///   - frame: the window frame about to be shown (AppKit coordinates, y up).
    ///   - visibleFrames: the `visibleFrame` of every connected screen.
    ///   - fallback: where to recover to — the main screen's `visibleFrame`.
    /// - Returns: `frame` when the center of its title bar lies on a visible
    ///   frame; otherwise `frame`, same size, centered in `fallback` and
    ///   clamped inside it. With no fallback (no screens), `frame` unchanged.
    public static func recoveredFrame(_ frame: CGRect, visibleFrames: [CGRect], fallback: CGRect?) -> CGRect {
        // the point just below the top edge, where the title bar is grabbed
        let titleBarCenter = CGPoint(x: frame.midX, y: frame.maxY - 1)
        if visibleFrames.contains(where: { $0.contains(titleBarCenter) }) {
            return frame
        }
        guard let fallback else { return frame }
        // the size is the window's own (Settings is not resizable); only the
        // origin moves. A window larger than the display keeps its top-left
        // corner, and so its title bar, on screen.
        var x = (fallback.midX - frame.width / 2).rounded()
        var y = (fallback.midY - frame.height / 2).rounded()
        if frame.width > fallback.width { x = fallback.minX }
        if frame.height > fallback.height { y = fallback.maxY - frame.height }
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }
}
