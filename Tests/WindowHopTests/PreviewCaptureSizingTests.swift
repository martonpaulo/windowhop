import XCTest
@testable import WindowHopCore

final class PreviewCaptureSizingTests: XCTestCase {
    private let ultrawideWindow = CGSize(width: 3440, height: 1415)
    private let canvas = CGSize(width: 302, height: 189)

    /// The regression: a 1x display presented every snapshot at half its canvas.
    func testANonRetinaCaptureFillsItsCanvas() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: ultrawideWindow, targetSize: canvas, scale: 1)
        let points = PreviewCaptureSizing.pointSize(pixelSize: pixels, scale: 1)

        XCTAssertEqual(points.width, canvas.width, accuracy: 1)
        XCTAssertLessThanOrEqual(points.height, canvas.height)
    }

    func testARetinaCaptureHasDoublePixelsAndTheSamePoints() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: ultrawideWindow, targetSize: canvas, scale: 2)
        let points = PreviewCaptureSizing.pointSize(pixelSize: pixels, scale: 2)

        XCTAssertEqual(pixels.width, canvas.width * 2, accuracy: 1)
        XCTAssertEqual(points.width, canvas.width, accuracy: 1)
    }

    func testTallWindowsFitTheCanvasHeight() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: CGSize(width: 800, height: 1600), targetSize: canvas, scale: 1)
        let points = PreviewCaptureSizing.pointSize(pixelSize: pixels, scale: 1)

        XCTAssertEqual(points.height, canvas.height, accuracy: 1)
        XCTAssertLessThanOrEqual(points.width, canvas.width)
    }

    func testTinyWindowsAreNeverCapturedAboveTwiceTheirSize() {
        let pixels = PreviewCaptureSizing.pixelSize(
            windowSize: CGSize(width: 40, height: 30), targetSize: canvas, scale: 2)

        XCTAssertEqual(pixels, CGSize(width: 80, height: 60))
    }
}
