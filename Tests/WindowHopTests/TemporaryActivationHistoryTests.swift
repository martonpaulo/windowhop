import AppKit
import XCTest
@testable import WindowHopCore

final class TemporaryActivationHistoryTests: XCTestCase {
    private var store: WindowStore!
    private var originWindow: NSWindow!
    private var targetWindow: NSWindow!

    override func setUp() {
        super.setUp()
        store = WindowStore()
        originWindow = makeWindow(title: "Origin")
        targetWindow = makeWindow(title: "Target")
        store.registerOwnWindow(targetWindow)
        store.registerOwnWindow(originWindow)
    }

    override func tearDown() {
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: originWindow)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: targetWindow)
        targetWindow = nil
        originWindow = nil
        store = nil
        super.tearDown()
    }

    func testTemporaryFocusDoesNotRewriteMRUAndCancelPreservesOrigin() {
        let origin = store.windows[0]
        let target = store.windows[1]

        store.beginTemporaryActivationSession()
        store.noteTemporaryActivation(target)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: targetWindow)
        store.finishTemporaryActivationSession(committedWindow: nil)
        // macOS may deliver a focus notification after the AX action queue has
        // completed; it is still temporary and must not become history.
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: targetWindow)

        XCTAssertTrue(store.windows[0] === origin)
    }

    func testOnlyCommittedWindowIsRecordedInMRU() {
        let target = store.windows[1]

        store.beginTemporaryActivationSession()
        store.noteTemporaryActivation(target)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: targetWindow)
        XCTAssertFalse(store.windows[0] === target)
        store.finishTemporaryActivationSession(committedWindow: target)

        XCTAssertTrue(store.windows[0] === target)
    }

    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.title = title
        return window
    }
}
