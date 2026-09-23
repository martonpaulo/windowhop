import AppKit
import XCTest

@testable import WindowHopCore

/// The Settings window's position survives relaunch through AppKit's frame
/// autosave, while its size always comes from the shared pane canvas.
/// Each test uses its own autosave name and removes AppKit's key afterwards.
@MainActor
final class SettingsWindowFrameTests: XCTestCase {
    private var autosaveName: String!
    private var windows: [NSWindow] = []
    private var isolated: IsolatedPreferences!

    private var defaultsKey: String { "NSWindow Frame \(autosaveName!)" }

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        isolated = IsolatedPreferences()
        autosaveName = "WindowHopSettingsTest-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        for window in windows {
            window.setFrameAutosaveName("")
            window.close()
        }
        windows = []
        isolated.remove()
        isolated = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        try await super.tearDown()
    }

    /// A new controller stands in for a new process: nothing retained.
    private func launch() -> NSWindow {
        let window = SettingsWindowController(
            dependencies: isolated.settingsDependencies,
            registerOwnWindow: { _ in },
            frameAutosaveName: autosaveName
        ).preparedWindow()
        windows.append(window)
        return window
    }

    /// Releases the autosave name, as quitting does, so the next launch can claim it.
    private func quit(_ window: NSWindow) {
        window.setFrameAutosaveName("")
    }

    private var screen: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
    }

    func testFirstUseIsCentered() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display")
        XCTAssertNil(UserDefaults.standard.string(forKey: defaultsKey))
        let window = launch()
        // AppKit's center() puts the window slightly above the true center
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 2)
        XCTAssertTrue(screen.contains(window.frame))
    }

    func testMovedPositionIsRestoredOnNextLaunch() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display")
        let first = launch()
        let origin = CGPoint(x: screen.minX + 40, y: screen.minY + 30)
        first.setFrameOrigin(origin)
        XCTAssertNotNil(
            UserDefaults.standard.string(forKey: defaultsKey),
            "AppKit saves the moved frame under the autosave name")
        quit(first)

        let second = launch()
        XCTAssertEqual(second.frame.origin, origin)
        XCTAssertEqual(second.frame.size, first.frame.size)
    }

    func testSavedFrameOfAnotherSizeKeepsTheCanvasSize() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display")
        let canvasSize = launch().frame.size
        windows.forEach(quit)

        // a frame saved by a build whose canvas had another size
        let old = NSWindow(
            contentRect: .zero, styleMask: [.titled, .resizable],
            backing: .buffered, defer: true)
        old.isReleasedWhenClosed = false
        windows.append(old)
        // anchored to the top with room below, so restoring the taller canvas never makes
        // AppKit push the window back on screen (CI runners have small displays)
        try XCTSkipIf(screen.height < canvasSize.height + 80, "display too small to restore the canvas")
        let savedHeight = canvasSize.height - 80
        let savedFrame = CGRect(
            x: screen.minX + 60, y: screen.maxY - 20 - savedHeight,
            width: canvasSize.width + 120, height: savedHeight)
        old.setFrame(savedFrame, display: false)
        old.saveFrame(usingName: autosaveName)

        let restored = launch()
        XCTAssertEqual(restored.frame.size, canvasSize)
        XCTAssertEqual(restored.frame.minX, savedFrame.minX)
        XCTAssertEqual(restored.frame.maxY, savedFrame.maxY, "the title bar stays where it was")
    }

    func testSavedFrameOnVanishedDisplayIsRecovered() throws {
        let main = try XCTUnwrap(NSScreen.main)
        let first = launch()
        quit(first)
        // far beyond every connected display
        let offScreen = CGRect(x: 100_000, y: 100_000, width: first.frame.width, height: first.frame.height)
        let old = NSWindow(
            contentRect: .zero, styleMask: [.titled],
            backing: .buffered, defer: true)
        old.isReleasedWhenClosed = false
        windows.append(old)
        old.setFrame(offScreen, display: false)
        old.saveFrame(usingName: autosaveName)

        let restored = launch()
        XCTAssertTrue(main.visibleFrame.contains(restored.frame))
        XCTAssertEqual(restored.frame.size, first.frame.size)
    }

    func testSwitchingPanesKeepsTheWindowSize() throws {
        let window = launch()
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        let original = tabs.selectedTabViewItemIndex
        let size = window.frame.size
        for index in tabs.tabViewItems.indices {
            tabs.selectedTabViewItemIndex = index
            XCTAssertEqual(window.frame.size, size, "pane \(index)")
        }
        tabs.selectedTabViewItemIndex = original
    }
}
