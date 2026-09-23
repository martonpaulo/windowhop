import AppKit
import XCTest

@testable import WindowHopCore
@testable import WindowHopKit

/// #38: the monitor turns lock, session and sleep notifications into `SessionAvailability`
/// events. Every notification goes to a private center: posting the real
/// `com.apple.screenIsLocked` on the system-wide distributed center would reach every
/// process on the Mac.
@MainActor
final class SessionMonitorTests: XCTestCase {
    private var distributed: NotificationCenter!
    private var workspace: NotificationCenter!
    private var received: [(SessionAvailability.Event, Bool)] = []
    private var monitor: SessionMonitor!

    override func setUp() async throws {
        distributed = NotificationCenter()
        workspace = NotificationCenter()
        received = []
        monitor = SessionMonitor(distributedCenter: distributed, workspaceCenter: workspace) {
            [weak self] event, needsRecovery in
            self?.received.append((event, needsRecovery))
        }
    }

    override func tearDown() async throws {
        monitor.stop()
        monitor = nil
    }

    func testLockAndUnlockNotificationsDriveOneRecovery() {
        distributed.post(name: SessionMonitor.screenLockedNotification, object: nil)
        XCTAssertFalse(monitor.availability.isUsable, "the lock makes AX answers untrusted")
        distributed.post(name: SessionMonitor.screenUnlockedNotification, object: nil)
        XCTAssertTrue(monitor.availability.isUsable)
        XCTAssertEqual(received.map(\.0), [.screenLocked, .screenUnlocked])
        XCTAssertEqual(received.map(\.1), [false, true], "only the unlock asks for the recovery pass")
    }

    func testTheLockNamesAreTheOnesLoginwindowPosts() {
        XCTAssertEqual(SessionMonitor.screenLockedNotification.rawValue, "com.apple.screenIsLocked")
        XCTAssertEqual(SessionMonitor.screenUnlockedNotification.rawValue, "com.apple.screenIsUnlocked")
    }

    func testWorkspaceNotificationsMapToSessionEvents() {
        let sequence: [(Notification.Name, SessionAvailability.Event)] = [
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResignedActive),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
            (NSWorkspace.screensDidSleepNotification, .displaysSlept),
            (NSWorkspace.screensDidWakeNotification, .displaysWoke),
            (NSWorkspace.willSleepNotification, .systemWillSleep),
            (NSWorkspace.didWakeNotification, .systemDidWake),
        ]
        for (name, _) in sequence { workspace.post(name: name, object: nil) }
        XCTAssertEqual(received.map(\.0), sequence.map(\.1))
        XCTAssertEqual(received.map(\.1), [false, true, false, true, false, true])
    }

    func testTheSystemWideCentersAreNotUsedWhenInjected() {
        // a lock posted anywhere else is not observed by this monitor
        NotificationCenter.default.post(name: SessionMonitor.screenLockedNotification, object: nil)
        XCTAssertTrue(monitor.availability.isUsable)
        XCTAssertTrue(received.isEmpty)
    }

    func testStopEndsObservation() {
        monitor.stop()
        distributed.post(name: SessionMonitor.screenLockedNotification, object: nil)
        XCTAssertTrue(monitor.availability.isUsable)
        XCTAssertTrue(received.isEmpty)
    }
}
