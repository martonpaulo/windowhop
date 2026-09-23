import CoreGraphics

/// The height of Sparkle's update window, fitted to its release notes (#128).
///
/// Sparkle keeps the window's last size (its frame autosave), so it opens either
/// too short, with the notes in a scroll view, or too tall, with empty space. The
/// window is resized once the notes have loaded: the notes area becomes exactly
/// as tall as their content, the top edge stays where it is, and the window
/// stays between its minimum height and the screen's visible height.
public enum UpdateAlertSizing {
    public static func fittedFrame(
        window: CGRect,
        notesViewHeight: CGFloat,
        contentHeight: CGFloat,
        minimumHeight: CGFloat,
        visibleScreen: CGRect
    ) -> CGRect {
        guard contentHeight > 0, notesViewHeight > 0 else { return window }
        let chrome = window.height - notesViewHeight
        let height = min(
            max(chrome + contentHeight.rounded(.up), minimumHeight),
            visibleScreen.height)
        var fitted = window
        fitted.origin.y = window.maxY - height
        fitted.size.height = height
        // grown past the bottom of the screen: move up, never above its top
        if fitted.minY < visibleScreen.minY {
            fitted.origin.y = visibleScreen.minY
        }
        return fitted
    }
}
