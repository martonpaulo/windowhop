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
    public static func pixelSize(windowSize: CGSize, targetSize: CGSize, scale: CGFloat) -> CGSize {
        guard windowSize.width > 0, windowSize.height > 0 else { return CGSize(width: 1, height: 1) }
        let fit = min(
            targetSize.width * scale / windowSize.width,
            targetSize.height * scale / windowSize.height, 2)
        return CGSize(
            width: max(1, (windowSize.width * fit).rounded(.down)),
            height: max(1, (windowSize.height * fit).rounded(.down)))
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
