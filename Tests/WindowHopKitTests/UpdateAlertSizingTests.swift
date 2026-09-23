import CoreGraphics
import Testing

@testable import WindowHopKit

/// Sparkle's update window fits its release notes (#128).
struct UpdateAlertSizingTests {
    private let screen = CGRect(x: 0, y: 0, width: 1720, height: 1409)
    /// 565 x 390 with a 195 pt notes area: the owner's short window.
    private let window = CGRect(x: 565, y: 600, width: 565, height: 390)

    @Test func aShortWindowGrowsDownToShowAllTheNotes() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 481,
            minimumHeight: 300, visibleScreen: screen)

        #expect(fitted.height == CGFloat(676))  // chrome 195 + notes 481
        #expect(fitted.maxY == window.maxY)
        #expect(fitted.width == window.width)
        #expect(fitted.minX == window.minX)
    }

    @Test func aTallWindowShrinksToTheNotes() {
        let tall = CGRect(x: 565, y: 406, width: 565, height: 951)
        let fitted = UpdateAlertSizing.fittedFrame(
            window: tall, notesViewHeight: 760, contentHeight: 300.4,
            minimumHeight: 300, visibleScreen: screen)

        #expect(fitted.height == CGFloat(492))  // chrome 191 + notes 301
        #expect(fitted.maxY == tall.maxY)
    }

    @Test func theWindowNeverGetsShorterThanItsMinimum() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 40,
            minimumHeight: 300, visibleScreen: screen)

        #expect(fitted.height == 300)
    }

    @Test func longNotesStopAtTheScreenAndScroll() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 5000,
            minimumHeight: 300, visibleScreen: screen)

        #expect(fitted.height == screen.height)
        #expect(fitted.minY == screen.minY)
    }

    @Test func growingPastTheBottomMovesTheWindowUp() {
        let low = CGRect(x: 565, y: 20, width: 565, height: 390)
        let fitted = UpdateAlertSizing.fittedFrame(
            window: low, notesViewHeight: 195, contentHeight: 600,
            minimumHeight: 300, visibleScreen: screen)

        #expect(fitted.minY == screen.minY)
        #expect(fitted.height == CGFloat(795))  // chrome 195 + notes 600
    }

    @Test func nothingMeasuredLeavesTheWindowAlone() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 0,
            minimumHeight: 300, visibleScreen: screen)

        #expect(fitted == window)
    }
}
