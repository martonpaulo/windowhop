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

    /// The frame that aspect-fits an image of `imageSize` inside `canvas`,
    /// centered, scaled up or down: every snapshot fills its card's width or
    /// height, and a window smaller than the card is enlarged rather than left
    /// floating in the middle (#33). Never crops.
    public static func fittedRect(imageSize: CGSize?, in canvas: CGRect) -> CGRect {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return canvas }
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: canvas.midX - fitted.width / 2,
            y: canvas.midY - fitted.height / 2,
            width: fitted.width, height: fitted.height)
    }
}
