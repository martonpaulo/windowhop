import CoreGraphics
import Testing

@testable import WindowHopKit

/// A snapshot fills its preview canvas on 1x and 2x displays alike (#33).
struct PreviewCaptureSizingTests {
    private let ultrawideWindow = CGSize(width: 3440, height: 1415)
    private let canvas = CGSize(width: 188, height: 118)

    /// The regression: a 1x display presented every snapshot at half its canvas.
    @Test func aNonRetinaCaptureFillsItsCanvas() {
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

    @Test func aTinyWindowIsCapturedAtNoMoreThanTwiceItsSize() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: CGSize(width: 20, height: 10), targetSize: canvas, scale: 2)

        #expect(pixels == CGSize(width: 40, height: 20))
    }

    @Test func anEmptyWindowStillGetsAValidCaptureSize() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: .zero, targetSize: canvas, scale: 2)

        #expect(pixels == CGSize(width: 1, height: 1))
    }

    /// A small snapshot is enlarged to the canvas, never left in its middle.
    @Test func aSmallImageIsScaledUpToFitTheCanvas() {
        let box = CGRect(origin: CGPoint(x: 8, y: 30), size: canvas)
        let fitted = PreviewCaptureSizing.fittedRect(
            imageSize: CGSize(width: 94, height: 59), in: box)

        #expect(abs(fitted.width - box.width) <= 1)
        #expect(fitted.height <= box.height + 1)
        #expect(abs(fitted.midX - box.midX) < 0.01)
        #expect(abs(fitted.midY - box.midY) < 0.01)
    }

    @Test func aTallImageFitsTheCanvasHeightWithoutCropping() {
        let box = CGRect(origin: .zero, size: canvas)
        let fitted = PreviewCaptureSizing.fittedRect(
            imageSize: CGSize(width: 100, height: 900), in: box)

        #expect(abs(fitted.height - box.height) < 0.01)
        #expect(fitted.width < box.width)
    }

    @Test func noImageFillsTheCanvas() {
        let box = CGRect(origin: .zero, size: canvas)
        #expect(PreviewCaptureSizing.fittedRect(imageSize: nil, in: box) == box)
    }
}
