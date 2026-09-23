import CoreGraphics
import XCTest
@testable import WindowHopKit

/// A restored Settings frame stays where the person put it while its title bar
/// is reachable, and returns to the main display when its display is gone.
final class WindowFrameRecoveryTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    private let window = CGSize(width: 560, height: 592)

    private func recovered(_ frame: CGRect, _ screens: [CGRect]) -> CGRect {
        WindowFrameRecovery.recoveredFrame(frame, visibleFrames: screens, fallback: screens.first)
    }

    func testFrameFullyOnScreenIsKept() {
        let frame = CGRect(origin: CGPoint(x: 100, y: 120), size: window)
        XCTAssertEqual(recovered(frame, [main]), frame)
    }

    func testFrameOnSecondDisplayIsKept() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 300), size: window)
        XCTAssertEqual(recovered(frame, [main, right]), frame)
    }

    func testFramePartlyOffScreenWithReachableTitleBarIsKept() {
        // dragged mostly below the bottom edge; the title bar is still grabbable
        let frame = CGRect(origin: CGPoint(x: 400, y: -500), size: window)
        XCTAssertEqual(recovered(frame, [main]), frame)
    }

    func testFrameOnVanishedDisplayIsCenteredOnMain() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 300), size: window)
        let result = recovered(frame, [main])
        XCTAssertEqual(result.size, window)
        XCTAssertEqual(result.midX, main.midX, accuracy: 1)
        XCTAssertEqual(result.midY, main.midY, accuracy: 1)
        XCTAssertTrue(main.contains(result))
    }

    func testFrameWithTitleBarAboveTheScreenIsRecovered() {
        let frame = CGRect(origin: CGPoint(x: 100, y: 800), size: window)
        let result = recovered(frame, [main])
        XCTAssertTrue(main.contains(result))
    }

    func testFrameLargerThanFallbackKeepsItsTitleBarOnScreen() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let frame = CGRect(origin: CGPoint(x: 5000, y: 5000), size: window)
        let result = WindowFrameRecovery.recoveredFrame(frame, visibleFrames: [small], fallback: small)
        XCTAssertEqual(result.size, window)
        XCTAssertEqual(result.minX, small.minX)
        XCTAssertEqual(result.maxY, small.maxY)
    }

    func testNoScreensLeavesFrameUnchanged() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 300), size: window)
        XCTAssertEqual(WindowFrameRecovery.recoveredFrame(frame, visibleFrames: [], fallback: nil), frame)
    }
}
