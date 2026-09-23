import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// #38: the monitor turns lock, session and sleep notifications into `SessionAvailability`
    /// events. Every notification goes to a private center: posting the real
    /// `com.apple.screenIsLocked` on the system-wide distributed center would reach every
    /// process on the Mac.
    @MainActor
    final class SessionMonitorTests {
        private var distributed: NotificationCenter!
        private var workspace: NotificationCenter!
        private var received: [(SessionAvailability.Event, Bool)] = []
        private var monitor: SessionMonitor!

        init() {
            distributed = NotificationCenter()
            workspace = NotificationCenter()
            received = []
            monitor = SessionMonitor(distributedCenter: distributed, workspaceCenter: workspace) {
                [weak self] event, needsRecovery in
                self?.received.append((event, needsRecovery))
            }
        }

        isolated deinit {
            monitor.stop()
            monitor = nil
        }

        @Test func lockAndUnlockNotificationsDriveOneRecovery() {
            distributed.post(name: SessionMonitor.screenLockedNotification, object: nil)
            #expect(!monitor.availability.isUsable, "the lock makes AX answers untrusted")
            distributed.post(name: SessionMonitor.screenUnlockedNotification, object: nil)
            #expect(monitor.availability.isUsable)
            #expect(received.map(\.0) == [.screenLocked, .screenUnlocked])
            #expect(received.map(\.1) == [false, true], "only the unlock asks for the recovery pass")
        }

        @Test func theLockNamesAreTheOnesLoginwindowPosts() {
            #expect(SessionMonitor.screenLockedNotification.rawValue == "com.apple.screenIsLocked")
            #expect(SessionMonitor.screenUnlockedNotification.rawValue == "com.apple.screenIsUnlocked")
        }

        @Test func workspaceNotificationsMapToSessionEvents() {
            let sequence: [(Notification.Name, SessionAvailability.Event)] = [
                (NSWorkspace.sessionDidResignActiveNotification, .sessionResignedActive),
                (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
                (NSWorkspace.screensDidSleepNotification, .displaysSlept),
                (NSWorkspace.screensDidWakeNotification, .displaysWoke),
                (NSWorkspace.willSleepNotification, .systemWillSleep),
                (NSWorkspace.didWakeNotification, .systemDidWake),
            ]
            for (name, _) in sequence { workspace.post(name: name, object: nil) }
            #expect(received.map(\.0) == sequence.map(\.1))
            #expect(received.map(\.1) == [false, true, false, true, false, true])
        }

        @Test func theSystemWideCentersAreNotUsedWhenInjected() {
            // a lock posted anywhere else is not observed by this monitor
            NotificationCenter.default.post(name: SessionMonitor.screenLockedNotification, object: nil)
            #expect(monitor.availability.isUsable)
            #expect(received.isEmpty)
        }

        @Test func stopEndsObservation() {
            monitor.stop()
            distributed.post(name: SessionMonitor.screenLockedNotification, object: nil)
            #expect(monitor.availability.isUsable)
            #expect(received.isEmpty)
        }
    }
}
