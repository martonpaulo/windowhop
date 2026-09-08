import AppKit
import XCTest
@testable import WindowHopCore

/// The expanded presentation wraps its snapshot instead of inheriting the grid
/// panel's measured frame, which turned it into a letterbox on wide displays.
final class ExpandedPreviewGeometryTests: XCTestCase {
    private let ultrawide = CGSize(width: 3440, height: 1440)
    private let laptop = CGSize(width: 1512, height: 916)
    private let tall = CGSize(width: 1080, height: 1920)

    private func chrome() -> CGSize {
        CGSize(width: DesignTokens.expandedPreviewPanelInset * 2,
               height: DesignTokens.expandedPreviewPanelInset * 2
                   + DesignTokens.expandedPreviewTitleHeight)
    }

    private func canvasAspect(_ panel: CGSize) -> CGFloat {
        (panel.width - chrome().width) / (panel.height - chrome().height)
    }

    private func fits(_ panel: CGSize, in visibleFrame: CGSize) -> Bool {
        panel.width <= visibleFrame.width * DesignTokens.panelMaxWidthFraction + 0.5
            && panel.height <= visibleFrame.height * DesignTokens.panelMaxHeightFraction + 0.5
    }

    func testCanvasTakesTheSnapshotShape() {
        for image in [CGSize(width: 1440, height: 900), CGSize(width: 900, height: 1440),
                      CGSize(width: 800, height: 800)] {
            let panel = DesignTokens.expandedPreviewPanelSize(imageSize: image,
                                                              visibleFrame: ultrawide)

            XCTAssertEqual(canvasAspect(panel), image.width / image.height, accuracy: 0.01,
                           "\(image) must keep its own shape")
        }
    }

    /// The regression this fixes: an ultrawide display must not stretch the
    /// panel into a strip, and the canvas must never exceed the screen.
    func testUltrawideDisplayNeverProducesALetterbox() {
        let panel = DesignTokens.expandedPreviewPanelSize(
            imageSize: CGSize(width: 1440, height: 900), visibleFrame: ultrawide)

        XCTAssertTrue(fits(panel, in: ultrawide))
        XCTAssertLessThan(canvasAspect(panel), 2, "no strip-shaped canvas")
    }

    func testOversizedSnapshotIsClampedToTheVisibleFrame() {
        for visibleFrame in [ultrawide, laptop, tall] {
            let panel = DesignTokens.expandedPreviewPanelSize(
                imageSize: CGSize(width: 6000, height: 4000), visibleFrame: visibleFrame)

            XCTAssertTrue(fits(panel, in: visibleFrame), "overflows \(visibleFrame)")
            XCTAssertEqual(canvasAspect(panel), 1.5, accuracy: 0.01)
        }
    }

    /// A tiny window still gets a usable panel rather than a postage stamp.
    func testSmallSnapshotStillReachesTheMinimumPanel() {
        let panel = DesignTokens.expandedPreviewPanelSize(
            imageSize: CGSize(width: 320, height: 200), visibleFrame: ultrawide)

        XCTAssertGreaterThanOrEqual(panel.width, DesignTokens.expandedPreviewMinimumWidth)
        XCTAssertGreaterThanOrEqual(panel.height, DesignTokens.expandedPreviewMinimumHeight)
    }

    func testNoSnapshotYetUsesTheSharedPreviewCanvasShape() {
        let panel = DesignTokens.expandedPreviewPanelSize(imageSize: nil,
                                                          visibleFrame: laptop)

        XCTAssertEqual(canvasAspect(panel), DesignTokens.previewCanvasAspect, accuracy: 0.01)
        XCTAssertTrue(fits(panel, in: laptop))
    }

    /// A screen smaller than the documented minimum still wins: the panel must
    /// stay on screen rather than honor the minimum.
    func testVerySmallScreenClampsBelowTheMinimum() {
        let small = CGSize(width: 640, height: 400)
        let panel = DesignTokens.expandedPreviewPanelSize(
            imageSize: CGSize(width: 1440, height: 900), visibleFrame: small)

        XCTAssertTrue(fits(panel, in: small))
    }
}
