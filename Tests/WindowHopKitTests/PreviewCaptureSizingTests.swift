import CoreGraphics
import Testing

@testable import WindowHopKit

/// A snapshot fills its preview canvas on 1x and 2x displays alike (#33).
struct PreviewCaptureSizingTests {
    private let ultrawideWindow = CGSize(width: 3440, height: 1415)
    private let canvas = CGSize(width: 188, height: 118)

    /// The regression: a 1x display presented every snapshot at half its canvas.
    /// The expanded preview still fits its window into the target.
    @Test func aNonRetinaFittedCaptureSpansItsCanvas() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: ultrawideWindow, targetSize: canvas, scale: 1)
        let points = PreviewCaptureSizing.pointSize(pixelSize: pixels, scale: 1)

        #expect(abs(points.width - canvas.width) <= 1)
        #expect(points.height <= canvas.height)
    }

    @Test func aRetinaCaptureHasDoublePixelsAndTheSamePoints() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: ultrawideWindow, targetSize: canvas, scale: 2)
        let points = PreviewCaptureSizing.pointSize(pixelSize: pixels, scale: 2)

        #expect(abs(pixels.width - canvas.width * 2) <= 1)
        #expect(abs(points.width - canvas.width) <= 1)
    }

    /// The regression: a tile fills its canvas (#127), so a capture sized to fit
    /// it left an ultrawide window 77 px tall in a 118 px card, stretched 1.5x.
    @Test(arguments: [1.0, 2.0])
    func aTileCaptureHasEnoughPixelsToCoverItsCanvas(scale: CGFloat) {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: ultrawideWindow, covering: canvas, scale: scale)
        let points = PreviewCaptureSizing.pointSize(pixelSize: pixels, scale: scale)
        let drawn = PreviewCaptureSizing.filledRect(
            imageSize: points, in: CGRect(origin: .zero, size: canvas))

        #expect(pixels.height >= canvas.height * scale)
        #expect(pixels.width >= canvas.width * scale)
        // presented without being scaled up
        #expect(drawn.width <= points.width + 1)
    }

    @Test func aTallWindowCoversTheCanvasWidth() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: CGSize(width: 600, height: 1200), covering: canvas, scale: 1)

        #expect(pixels.width >= canvas.width)
        #expect(pixels.height >= canvas.height)
    }

    @Test func aTinyWindowIsCapturedAtNoMoreThanTwiceItsSize() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: CGSize(width: 20, height: 10), targetSize: canvas, scale: 2)

        #expect(pixels == CGSize(width: 40, height: 20))
    }

    @Test func aTinyWindowIsCoveredAtNoMoreThanTwiceItsSize() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: CGSize(width: 20, height: 10), covering: canvas, scale: 2)

        #expect(pixels == CGSize(width: 40, height: 20))
    }

    @Test func anEmptyWindowStillGetsAValidCaptureSize() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: .zero, targetSize: canvas, scale: 2)
        let covering = PreviewCaptureSizing.pixelSize(
            windowSize: .zero, covering: canvas, scale: 2)

        #expect(pixels == CGSize(width: 1, height: 1))
        #expect(covering == CGSize(width: 1, height: 1))
    }

    /// Any snapshot covers the whole canvas, centred; the canvas clips the rest (#127).
    @Test(arguments: [
        CGSize(width: 94, height: 59), CGSize(width: 3440, height: 1440),
        CGSize(width: 100, height: 900), CGSize(width: 4, height: 4),
    ])
    func aSnapshotCoversTheCanvas(imageSize: CGSize) {
        let box = CGRect(origin: CGPoint(x: 8, y: 30), size: canvas)
        let filled = PreviewCaptureSizing.filledRect(imageSize: imageSize, in: box)

        #expect(filled.insetBy(dx: -0.01, dy: -0.01).contains(box))
        #expect(abs(filled.midX - box.midX) < 0.01)
        #expect(abs(filled.midY - box.midY) < 0.01)
        // one side matches the canvas exactly, so the crop is as small as it can be
        #expect(abs(filled.width - box.width) < 0.01 || abs(filled.height - box.height) < 0.01)
    }

    @Test func noImageFillsTheCanvas() {
        let box = CGRect(origin: .zero, size: canvas)
        #expect(PreviewCaptureSizing.filledRect(imageSize: nil, in: box) == box)
    }
}
