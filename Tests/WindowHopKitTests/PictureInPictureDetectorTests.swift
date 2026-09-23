import CoreGraphics
import Foundation
import Testing

@testable import WindowHopKit

/// Behavior-based PiP detection: a floating (nonzero-layer) window server
/// entry marks a window as Picture in Picture, unless it covers a whole
/// screen (Keynote presentations and fullscreen overlays stay listed).
/// Layer values are real ones: Brave's PiP floats at layer 3, normal
/// windows at 0.
struct PictureInPictureDetectorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let pipFrame = CGRect(x: 1153, y: 668, width: 343, height: 193)

    private func onScreen(
        _ layer: Int, pid: pid_t = 100,
        frame: CGRect? = nil
    ) -> PictureInPictureDetector.OnScreenWindow {
        PictureInPictureDetector.OnScreenWindow(pid: pid, frame: frame ?? pipFrame, layer: layer)
    }

    @Test func floatingSmallWindowIsPictureInPicture() {
        #expect(
            PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: pipFrame,
                onScreenWindows: [onScreen(3)], screenFrames: [screen]))
    }

    @Test func normalLayerWindowIsNot() {
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: pipFrame,
                onScreenWindows: [onScreen(0)], screenFrames: [screen]))
    }

    @Test func floatingScreenCoveringWindowStaysListed() {
        // Keynote presentation mode: floating, but effectively fullscreen
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: screen,
                onScreenWindows: [onScreen(20, frame: screen)], screenFrames: [screen]))
    }

    @Test func unmatchedWindowResolvesToNotPiP() {
        // frame drifted beyond tolerance, or the window is not on screen
        let elsewhere = CGRect(x: 40, y: 40, width: 343, height: 193)
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: elsewhere,
                onScreenWindows: [onScreen(3)], screenFrames: [screen]))
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: nil,
                onScreenWindows: [onScreen(3)], screenFrames: [screen]))
    }

    @Test func matchRequiresTheOwningProcess() {
        // another app's floating window at the same coordinates is no evidence
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 200, frame: pipFrame,
                onScreenWindows: [onScreen(3, pid: 100)], screenFrames: [screen]))
    }

    // Measured facts (#90): an AppKit titled document window set to .floating
    // (layer 3, 360×252) keeps enabled close/minimize/zoom buttons; Chromium PiP
    // (Chrome for Testing and Brave, layer 3, 308×173) keeps all three buttons
    // but disabled.
    private let floatingDocument = CGRect(x: 440, y: 128, width: 360, height: 252)
    private let chromiumPiP = CGRect(x: 1114, y: 709, width: 308, height: 173)

    @Test func floatingDocumentWithStandardButtonsIsNotPictureInPicture() {
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: floatingDocument, buttons: .init(close: true, minimize: true, zoom: true),
                onScreenWindows: [onScreen(3, frame: floatingDocument)], screenFrames: [screen]))
        // a closable-only floating window at modal-panel level is ordinary too
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: floatingDocument, buttons: .init(close: true),
                onScreenWindows: [onScreen(8, frame: floatingDocument)], screenFrames: [screen]))
    }

    @Test func chromiumPiPWithDisabledButtonsIsPictureInPicture() {
        #expect(
            PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: chromiumPiP, buttons: .init(close: false, minimize: false, zoom: false),
                onScreenWindows: [onScreen(3, frame: chromiumPiP)], screenFrames: [screen]))
    }

    // Firefox and Zen PiP (AeroSpace corpus, #117): layer 3, close and zoom
    // (full screen) enabled, minimize disabled.
    private let firefoxPiPButtons = PictureInPictureDetector.TitleBarButtons(
        close: true, minimize: false, zoom: true)

    @Test func firefoxPiPWithOnlyMinimizeDisabledIsPictureInPicture() {
        #expect(
            PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: chromiumPiP, buttons: firefoxPiPButtons,
                onScreenWindows: [onScreen(3, frame: chromiumPiP)], screenFrames: [screen]))
    }

    @Test func firefoxButtonPatternAtTheNormalLayerIsNotPictureInPicture() {
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: floatingDocument, buttons: firefoxPiPButtons,
                onScreenWindows: [onScreen(0, frame: floatingDocument)], screenFrames: [screen]))
    }

    @Test func otherClosableFloatingWindowsAreNotPictureInPicture() {
        // #90's closable-only windows disable zoom too (macOS Join Network: close
        // enabled, minimize and zoom disabled); a missing minimize or zoom button,
        // or an enabled minimize button, never matches the Firefox pattern
        let patterns: [PictureInPictureDetector.TitleBarButtons] = [
            .init(close: true, minimize: false, zoom: false),
            .init(close: true, minimize: false),
            .init(close: true, zoom: true),
            .init(close: true, minimize: true, zoom: false),
        ]
        for buttons in patterns {
            #expect(
                !PictureInPictureDetector.isPictureInPicture(
                    pid: 100, frame: floatingDocument, buttons: buttons,
                    onScreenWindows: [onScreen(3, frame: floatingDocument)], screenFrames: [screen]),
                "\(buttons)")
        }
    }

    @Test func buttonlessOrUnreadFloatingWindowKeepsTheLayerRule() {
        // no close button, or its state never read: the floating layer alone decides
        #expect(
            PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: chromiumPiP, buttons: .init(),
                onScreenWindows: [onScreen(3, frame: chromiumPiP)], screenFrames: [screen]))
    }

    @Test func buttonlessModalAlertIsNotPictureInPicture() {
        // Measured (#115): an app-modal NSAlert or NSOpenPanel floats at layer 8
        // and has no close button, like Ghostty's update alert in AeroSpace's corpus
        let alert = CGRect(x: 590, y: 205, width: 260, height: 176)
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: alert, buttons: .init(),
                onScreenWindows: [onScreen(8, frame: alert)], screenFrames: [screen]))
    }

    @Test func fullscreenFloatingSurfaceStaysEligible() {
        // the fullscreen exception holds whatever the title bar reports
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: screen, buttons: .init(close: false),
                onScreenWindows: [onScreen(20, frame: screen)], screenFrames: [screen]))
    }

    @Test func disabledButtonsAloneNeverMakeANormalWindowPiP() {
        #expect(
            !PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: floatingDocument, buttons: .init(close: false),
                onScreenWindows: [onScreen(0, frame: floatingDocument)], screenFrames: [screen]))
    }

    @Test func smallFrameDriftStillMatches() {
        // AX and window-server frames can disagree by a pixel or two
        let drifted = pipFrame.offsetBy(dx: 2, dy: -2)
        #expect(
            PictureInPictureDetector.isPictureInPicture(
                pid: 100, frame: drifted,
                onScreenWindows: [onScreen(3)], screenFrames: [screen]))
    }
}
