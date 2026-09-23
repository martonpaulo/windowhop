import CoreGraphics
import Foundation
import Testing

@testable import WindowHopCore

/// The CGEvent tap calls its C callback on the event-tap thread, never on main.
/// Under Swift 6 a callback that inherits `EventTap`'s main-actor isolation traps at
/// the first key event, which no main-thread test would notice.
@MainActor
struct EventTapCallbackTests {
    private struct CallbackOutcome: Sendable {
        let onMainThread: Bool
        let passedThrough: Bool
    }

    @Test(.timeLimit(.minutes(1)))
    func callbackRunsOffTheMainThreadWithoutAnIsolationTrap() async throws {
        // an address is Sendable as an integer; the tap outlives the callback
        // because this test holds it until the wait below returns
        let tap = EventTap()
        let tapAddress = Int(bitPattern: Unmanaged.passUnretained(tap).toOpaque())
        // the background thread only reports; the assertions run on the test's own task
        let outcome: CallbackOutcome? = await withCheckedContinuation { passed in
            Thread.detachNewThread {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true),
                    let proxy = OpaquePointer(bitPattern: 1)
                else {
                    passed.resume(returning: nil)
                    return
                }
                // the tap is not started, so the event passes through untouched
                let result = eventTapCallback(proxy, .keyDown, event, UnsafeMutableRawPointer(bitPattern: tapAddress))
                passed.resume(
                    returning: CallbackOutcome(onMainThread: Thread.isMainThread, passedThrough: result != nil))
            }
        }
        let callback = try #require(outcome, "callback returned on a background thread")
        #expect(!callback.onMainThread)
        #expect(callback.passedThrough)
        withExtendedLifetime(tap) {}
    }
}
