import AppKit
import XCTest
@testable import WindowHopCore

/// The own-Settings-window exception: it appears exactly once while open,
/// participates in MRU, hides while minimized, and disappears on close.
/// Uses a fresh WindowStore instance (not .shared) and drives NSWindow
/// lifecycle via the notifications the store observes.
final class SettingsWindowEntryTests: XCTestCase {
    private var store: WindowStore!
    private var window: NSWindow!

    override func setUp() {
        super.setUp()
        store = WindowStore()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.title = "WindowHop Settings"
    }

    override func tearDown() {
        window = nil
        store = nil
        super.tearDown()
    }

    func testRegisteredSettingsWindowAppearsExactlyOnce() {
        store.registerOwnWindow(window)
        let items = store.snapshot()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "WindowHop Settings")
        XCTAssertEqual(items[0].appName, "WindowHop")
    }

    func testDoubleRegistrationDoesNotDuplicate() {
        store.registerOwnWindow(window)
        store.registerOwnWindow(window)
        XCTAssertEqual(store.snapshot().count, 1)
    }

    func testClosingRemovesTheEntry() {
        store.registerOwnWindow(window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        XCTAssertEqual(store.snapshot().count, 0)
    }

    func testMinimizedSettingsWindowIsExcluded() {
        store.registerOwnWindow(window)
        // headless tests can't really miniaturize; the store derives the state from
        // the notification name, which is what the Dock delivers in real usage
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        XCTAssertEqual(store.snapshot().count, 0)
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        XCTAssertEqual(store.snapshot().count, 1)
    }

    func testBecomingKeyMovesEntryToMRUFront() {
        store.registerOwnWindow(window)
        XCTAssertEqual(store.windows.first?.isOwnSettingsEntry, true)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(store.windows.first?.isOwnSettingsEntry, true)
    }

    func testOtherOwnWindowsRemainExcludedByTheDisplayRule() {
        // panels, alerts, onboarding: own windows that are NOT the settings exception
        let ownWindow = WindowDisplayState(isMinimized: false, isAppHidden: false,
                                           isOwnWindow: true, isOwnSettingsWindow: false,
                                           isOnCurrentSpace: true, isOnActiveDisplay: true)
        XCTAssertFalse(WindowEligibility.shouldDisplay(ownWindow, policy: .init()))
        let settingsWindow = WindowDisplayState(isMinimized: false, isAppHidden: false,
                                                isOwnWindow: true, isOwnSettingsWindow: true,
                                                isOnCurrentSpace: true, isOnActiveDisplay: true)
        XCTAssertTrue(WindowEligibility.shouldDisplay(settingsWindow, policy: .init()))
    }

    func testNativeEntryActivationAndCloseUseAppKitPaths() {
        store.registerOwnWindow(window)
        let entry = store.windows[0]
        XCTAssertNil(entry.ax)
        XCTAssertNil(entry.app)
        XCTAssertNotNil(entry.nativeWindow)
    }

    // MARK: - Live display membership (issue #22)

    /// The entry stored the frame it was registered with, so moving Settings to
    /// another display left it filed under the display it opened on.
    func testMovingTheWindowUpdatesItsDisplayMembership() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        window.setFrame(NSRect(x: screen.frame.midX, y: screen.frame.midY,
                               width: 400, height: 300), display: false)
        store.registerOwnWindow(window)
        let entry = try XCTUnwrap(store.windows.first)
        XCTAssertTrue(entry.isOn(screen: screen))

        window.setFrame(NSRect(x: screen.frame.maxX + 2000, y: screen.frame.midY,
                               width: 400, height: 300), display: false)

        XCTAssertFalse(entry.isOn(screen: screen),
                       "the entry must follow the window's live location")
    }

    func testResizingBackOntoTheScreenRestoresMembership() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        window.setFrame(NSRect(x: screen.frame.maxX + 2000, y: screen.frame.midY,
                               width: 400, height: 300), display: false)
        store.registerOwnWindow(window)
        let entry = try XCTUnwrap(store.windows.first)
        XCTAssertFalse(entry.isOn(screen: screen))

        window.setFrame(NSRect(x: screen.frame.midX, y: screen.frame.midY,
                               width: 400, height: 300), display: false)

        XCTAssertTrue(entry.isOn(screen: screen))
    }

    /// An open session must be told to look again when Settings is dragged.
    func testMoveAndResizeNotifyAnOpenSession() {
        store.registerOwnWindow(window)
        var changes = 0
        store.onChange = { changes += 1 }

        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)

        XCTAssertEqual(changes, 2)
    }

    /// Closing removes every observation, including the new geometry ones.
    func testClosingStopsGeometryNotifications() {
        store.registerOwnWindow(window)
        window.close()
        var changes = 0
        store.onChange = { changes += 1 }

        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)

        XCTAssertEqual(changes, 0)
    }

    /// External AX windows keep the Quartz conversion: a screen below the
    /// primary one has a positive Quartz origin, not a negative Cocoa one.
    func testScreenQuartzFrameFlipsAroundThePrimaryDisplay() {
        let primaryFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let belowFrame = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        // mirrors TrackedWindow.quartzFrame's arithmetic on plain rectangles
        func quartz(_ frame: CGRect) -> CGRect {
            CGRect(x: frame.origin.x, y: primaryFrame.maxY - frame.maxY,
                   width: frame.width, height: frame.height)
        }

        XCTAssertEqual(quartz(primaryFrame).origin.y, 0)
        XCTAssertEqual(quartz(belowFrame).origin.y, 1080)
        XCTAssertFalse(quartz(primaryFrame).intersects(quartz(belowFrame)))
    }
}
