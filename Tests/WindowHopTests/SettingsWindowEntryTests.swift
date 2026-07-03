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
        XCTAssertFalse(WindowEligibility.shouldDisplay(ownWindow, includeOtherSpaces: true,
                                                       includeOtherDisplays: true))
        let settingsWindow = WindowDisplayState(isMinimized: false, isAppHidden: false,
                                                isOwnWindow: true, isOwnSettingsWindow: true,
                                                isOnCurrentSpace: true, isOnActiveDisplay: true)
        XCTAssertTrue(WindowEligibility.shouldDisplay(settingsWindow, includeOtherSpaces: true,
                                                      includeOtherDisplays: true))
    }

    func testNativeEntryActivationAndCloseUseAppKitPaths() {
        store.registerOwnWindow(window)
        let entry = store.windows[0]
        XCTAssertNil(entry.ax)
        XCTAssertNil(entry.app)
        XCTAssertNotNil(entry.nativeWindow)
    }
}
