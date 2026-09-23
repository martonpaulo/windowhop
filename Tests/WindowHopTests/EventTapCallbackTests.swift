import CoreGraphics
import XCTest
@testable import WindowHopCore

/// The CGEvent tap calls its C callback on the event-tap thread, never on main.
/// Under Swift 6 a callback that inherits `EventTap`'s main-actor isolation traps at
/// the first key event, which no main-thread test would notice.
final class EventTapCallbackTests: XCTestCase {
    func testCallbackRunsOffTheMainThreadWithoutAnIsolationTrap() {
        // an address is Sendable as an integer; the tap outlives the callback
        // because this test holds it until the wait below returns
        let tap = MainActor.assumeIsolated { EventTap() }
        let tapAddress = MainActor.assumeIsolated {
            Int(bitPattern: Unmanaged.passUnretained(tap).toOpaque())
        }
        let passed = expectation(description: "callback returned on a background thread")
        Thread.detachNewThread {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true),
                  let proxy = OpaquePointer(bitPattern: 1) else { return }
            // the tap is not started, so the event passes through untouched
            let result = eventTapCallback(proxy, .keyDown, event, UnsafeMutableRawPointer(bitPattern: tapAddress))
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertNotNil(result)
            passed.fulfill()
        }
        wait(for: [passed], timeout: 5)
        withExtendedLifetime(tap) {}
    }
}
