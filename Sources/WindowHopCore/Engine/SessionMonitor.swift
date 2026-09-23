import AppKit
import WindowHopKit

/// Feeds the operating-system events that start and end a dark period (screen lock,
/// fast user switching, system and display sleep) to the pure `SessionAvailability`
/// rule, and reports each one to its owner, `WindowStore` (#38). Observation only: no
/// timer, and nothing runs between events.
@MainActor
final class SessionMonitor {
    /// Posted by loginwindow on `DistributedNotificationCenter` when the screen locks and
    /// unlocks. No SDK header declares these names, but the API that delivers them is
    /// public: the same exception as undeclared AX attribute strings (AGENTS.md "Public
    /// Apple APIs only", Decided on #38). AltTab relies on the same pair
    /// (upstream `97ec5cb1`, `src/events/ScreenLockEvents.swift`). If they stop firing,
    /// the session is never marked locked and behavior falls back to what it was before.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private(set) var availability = SessionAvailability()
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// `onEvent` runs on main after the rule has applied the event; `needsRecovery` is the
    /// rule's request for one recovery re-enumeration. Tests pass private centers so they
    /// never post a system-wide notification.
    init(
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onEvent: @escaping @MainActor (SessionAvailability.Event, _ needsRecovery: Bool) -> Void
    ) {
        let events: [(NotificationCenter, Notification.Name, SessionAvailability.Event)] = [
            (distributedCenter, Self.screenLockedNotification, .screenLocked),
            (distributedCenter, Self.screenUnlockedNotification, .screenUnlocked),
            (workspaceCenter, NSWorkspace.sessionDidResignActiveNotification, .sessionResignedActive),
            (workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
            (workspaceCenter, NSWorkspace.screensDidSleepNotification, .displaysSlept),
            (workspaceCenter, NSWorkspace.screensDidWakeNotification, .displaysWoke),
            (workspaceCenter, NSWorkspace.willSleepNotification, .systemWillSleep),
            (workspaceCenter, NSWorkspace.didWakeNotification, .systemDidWake),
        ]
        for (center, name, event) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let needsRecovery = self.availability.apply(event)
                    onEvent(event, needsRecovery)
                }
            }
            observers.append((center, token))
        }
    }

    func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
    }
}
