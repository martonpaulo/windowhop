import CoreGraphics

/// How large a window capture is, in pixels and in points (#33).
///
/// A capture is requested in pixels for the display's backing scale and must be
/// presented at those pixels divided by that same scale. Presenting it at a fixed
/// half size assumed every display is Retina, so on a 1x display each snapshot
/// drew at half its canvas.
public enum PreviewCaptureSizing {
    /// Pixel dimensions that fit a window into `targetSize` points at `scale`,
    /// keeping the window's aspect ratio and never exceeding twice its own size.
    /// For the expanded preview, which shows the whole window.
    public static func pixelSize(windowSize: CGSize, targetSize: CGSize, scale: CGFloat) -> CGSize {
        guard windowSize.width > 0, windowSize.height > 0 else { return CGSize(width: 1, height: 1) }
        return scaled(
            windowSize,
            by: min(
                targetSize.width * scale / windowSize.width,
                targetSize.height * scale / windowSize.height),
            rounding: .down)
    }

    /// Pixel dimensions that cover `targetSize` points at `scale`: the size a
    /// tile draws after `filledRect`, so its snapshot is never scaled up. A fitted
    /// capture of a 2.4:1 window was 77 px tall in a 118 px card and drew 1.5x
    /// enlarged and blurred on a 1x ultrawide display (#127).
    public static func pixelSize(windowSize: CGSize, covering targetSize: CGSize, scale: CGFloat) -> CGSize {
        guard windowSize.width > 0, windowSize.height > 0 else { return CGSize(width: 1, height: 1) }
        return scaled(
            windowSize,
            by: max(
                targetSize.width * scale / windowSize.width,
                targetSize.height * scale / windowSize.height),
            rounding: .up)
    }

    /// A fit rounds down so it never spills its target; a cover rounds up so it
    /// never falls a pixel short of its canvas.
    private static func scaled(
        _ windowSize: CGSize, by factor: CGFloat, rounding: FloatingPointRoundingRule
    ) -> CGSize {
        let factor = min(factor, 2)
        return CGSize(
            width: max(1, (windowSize.width * factor).rounded(rounding)),
            height: max(1, (windowSize.height * factor).rounded(rounding)))
    }

    /// The point size to present a capture of `pixelSize` taken for `scale`.
    public static func pointSize(pixelSize: CGSize, scale: CGFloat) -> CGSize {
        let scale = max(1, scale)
        return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }

    /// The frame that covers `canvas` with an image of `imageSize`, centred and
    /// scaled up or down (aspect-fill). The canvas's rounded shape clips the
    /// overflow, so a card is always full: the owner chose a few cropped pixels
    /// over a snapshot floating inside its card (#127, superseding #33's fit).
    public static func filledRect(imageSize: CGSize?, in canvas: CGRect) -> CGRect {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return canvas }
        let scale = max(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let filled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: canvas.midX - filled.width / 2,
            y: canvas.midY - filled.height / 2,
            width: filled.width, height: filled.height)
    }
}
