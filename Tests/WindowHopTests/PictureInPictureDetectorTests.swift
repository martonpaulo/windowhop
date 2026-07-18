import CoreGraphics
import XCTest
@testable import WindowHopCore

/// Behavior-based PiP detection: a floating (nonzero-layer) window server
/// entry marks a window as Picture in Picture, unless it covers a whole
/// screen (Keynote presentations and fullscreen overlays stay listed).
/// Layer values are real ones: Brave's PiP floats at layer 3, normal
/// windows at 0.
final class PictureInPictureDetectorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let pipFrame = CGRect(x: 1153, y: 668, width: 343, height: 193)

    private func onScreen(_ layer: Int, pid: pid_t = 100,
                          frame: CGRect? = nil) -> PictureInPictureDetector.OnScreenWindow {
        PictureInPictureDetector.OnScreenWindow(pid: pid, frame: frame ?? pipFrame, layer: layer)
    }

    func testFloatingSmallWindowIsPictureInPicture() {
        XCTAssertTrue(PictureInPictureDetector.isPictureInPicture(
            pid: 100, frame: pipFrame,
            onScreenWindows: [onScreen(3)], screenFrames: [screen]))
    }

    func testNormalLayerWindowIsNot() {
        XCTAssertFalse(PictureInPictureDetector.isPictureInPicture(
            pid: 100, frame: pipFrame,
            onScreenWindows: [onScreen(0)], screenFrames: [screen]))
    }

    func testFloatingScreenCoveringWindowStaysListed() {
        // Keynote presentation mode: floating, but effectively fullscreen
        XCTAssertFalse(PictureInPictureDetector.isPictureInPicture(
            pid: 100, frame: screen,
            onScreenWindows: [onScreen(20, frame: screen)], screenFrames: [screen]))
    }

    func testUnmatchedWindowResolvesToNotPiP() {
        // frame drifted beyond tolerance, or the window is not on screen
        let elsewhere = CGRect(x: 40, y: 40, width: 343, height: 193)
        XCTAssertFalse(PictureInPictureDetector.isPictureInPicture(
            pid: 100, frame: elsewhere,
            onScreenWindows: [onScreen(3)], screenFrames: [screen]))
        XCTAssertFalse(PictureInPictureDetector.isPictureInPicture(
            pid: 100, frame: nil,
            onScreenWindows: [onScreen(3)], screenFrames: [screen]))
    }

    func testMatchRequiresTheOwningProcess() {
        // another app's floating window at the same coordinates is no evidence
        XCTAssertFalse(PictureInPictureDetector.isPictureInPicture(
            pid: 200, frame: pipFrame,
            onScreenWindows: [onScreen(3, pid: 100)], screenFrames: [screen]))
    }

    func testSmallFrameDriftStillMatches() {
        // AX and window-server frames can disagree by a pixel or two
        let drifted = pipFrame.offsetBy(dx: 2, dy: -2)
        XCTAssertTrue(PictureInPictureDetector.isPictureInPicture(
            pid: 100, frame: drifted,
            onScreenWindows: [onScreen(3)], screenFrames: [screen]))
    }
}
