import CoreGraphics
import Foundation
import Testing

@testable import WindowHopKit

/// A restored Settings frame stays where the person put it while its title bar
/// is reachable, and returns to the main display when its display is gone.
struct WindowFrameRecoveryTests {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    private let window = CGSize(width: 560, height: 592)

    private func recovered(_ frame: CGRect, _ screens: [CGRect]) -> CGRect {
        WindowFrameRecovery.recoveredFrame(frame, visibleFrames: screens, fallback: screens.first)
    }

    @Test func frameFullyOnScreenIsKept() {
        let frame = CGRect(origin: CGPoint(x: 100, y: 120), size: window)
        #expect(recovered(frame, [main]) == frame)
    }

    @Test func frameOnSecondDisplayIsKept() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 300), size: window)
        #expect(recovered(frame, [main, right]) == frame)
    }

    @Test func framePartlyOffScreenWithReachableTitleBarIsKept() {
        // dragged mostly below the bottom edge; the title bar is still grabbable
        let frame = CGRect(origin: CGPoint(x: 400, y: -500), size: window)
        #expect(recovered(frame, [main]) == frame)
    }

    @Test func frameOnVanishedDisplayIsCenteredOnMain() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 300), size: window)
        let result = recovered(frame, [main])
        #expect(result.size == window)
        #expect(abs(result.midX - main.midX) <= 1)
        #expect(abs(result.midY - main.midY) <= 1)
        #expect(main.contains(result))
    }

    @Test func frameWithTitleBarAboveTheScreenIsRecovered() {
        let frame = CGRect(origin: CGPoint(x: 100, y: 800), size: window)
        let result = recovered(frame, [main])
        #expect(main.contains(result))
    }

    @Test func frameLargerThanFallbackKeepsItsTitleBarOnScreen() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let frame = CGRect(origin: CGPoint(x: 5000, y: 5000), size: window)
        let result = WindowFrameRecovery.recoveredFrame(frame, visibleFrames: [small], fallback: small)
        #expect(result.size == window)
        #expect(result.minX == small.minX)
        #expect(result.maxY == small.maxY)
    }

    @Test func noScreensLeavesFrameUnchanged() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 300), size: window)
        #expect(WindowFrameRecovery.recoveredFrame(frame, visibleFrames: [], fallback: nil) == frame)
    }
}
