import AppKit
import ApplicationServices

/// One running application we observe, ported from AltTab v10.12.0's Application.
/// A single AXObserver per app carries both app-level and window-level notifications.
/// Subscription is retried because apps mid-launch return .cannotComplete for a while.
public final class TrackedApp {
    static let appNotifications = [
        kAXApplicationActivatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]
    static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]
    private static let subscriptionRetries = 30
    private static let subscriptionRetryDelay = 0.5

    public let runningApplication: NSRunningApplication
    public let pid: pid_t
    public let axElement: AXUIElement
    public private(set) var name: String?
    public let bundleIdentifier: String?
    let executablePath: String?
    public internal(set) var isHidden: Bool
    private var axObserver: AXObserver?
    private var isReallyFinishedLaunching = false
    private var kvObservers: [NSKeyValueObservation] = []
    private var cachedIcon: NSImage?

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        pid = runningApplication.processIdentifier
        axElement = AXUIElementCreateApplication(pid)
        name = runningApplication.localizedName
        bundleIdentifier = runningApplication.bundleIdentifier
        executablePath = runningApplication.executableURL?.path
        isHidden = runningApplication.isHidden
        // some apps have activationPolicy .prohibited at launch and become .regular later;
        // isFinishedLaunching flips when the AX server may finally be reachable
        kvObservers = [
            runningApplication.observe(\.isFinishedLaunching, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.observeIfEligible() }
            },
            runningApplication.observe(\.activationPolicy, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.observeIfEligible() }
            },
        ]
        observeIfEligible()
    }

    public var icon: NSImage? {
        if cachedIcon == nil {
            cachedIcon = runningApplication.icon
        }
        return cachedIcon
    }

    func windowFacts(from attributes: AXAttributes) -> WindowFacts {
        WindowFacts(role: attributes.role,
                    subrole: attributes.subrole,
                    size: attributes.size,
                    title: attributes.title,
                    bundleIdentifier: bundleIdentifier,
                    localizedAppName: name,
                    executablePath: executablePath)
    }

    func observeIfEligible() {
        guard runningApplication.activationPolicy != .prohibited, !isReallyFinishedLaunching else { return }
        if axObserver == nil {
            var observer: AXObserver?
            AXObserverCreate(pid, AXNotificationRouter.axObserverCallback, &observer)
            guard let observer else { return }
            axObserver = observer
            CFRunLoopAddSource(BackgroundWork.axEventsThread.runLoop,
                               AXObserverGetRunLoopSource(observer), .commonModes)
        }
        subscribeToAppNotifications()
    }

    /// The first successful subscription marks the app as really finished launching
    /// (some apps report isFinishedLaunching but still return .cannotComplete);
    /// only then are its existing windows discovered.
    private func subscribeToAppNotifications() {
        guard let axObserver else { return }
        let element = axElement
        BackgroundWork.axReadsQueue.retrying(attempts: TrackedApp.subscriptionRetries,
                                             delay: TrackedApp.subscriptionRetryDelay) { [weak self] in
            guard let self, !self.isReallyFinishedLaunching else { return }
            if try element.subscribe(axObserver, TrackedApp.appNotifications.first!) {
                self.isReallyFinishedLaunching = true
                for notification in TrackedApp.appNotifications.dropFirst() {
                    BackgroundWork.axReadsQueue.retrying(attempts: TrackedApp.subscriptionRetries,
                                                         delay: TrackedApp.subscriptionRetryDelay) {
                        try element.subscribe(axObserver, notification)
                    }
                }
                DispatchQueue.main.async {
                    WindowStore.shared.discoverWindows(of: self)
                }
            }
        }
    }

    /// Adds window-level notifications for a newly discovered window element.
    /// Runs on the AX reads queue.
    func subscribeToWindowNotifications(_ windowElement: AXUIElement) {
        guard let axObserver else { return }
        for notification in TrackedApp.windowNotifications {
            BackgroundWork.axReadsQueue.retrying(attempts: TrackedApp.subscriptionRetries,
                                                 delay: TrackedApp.subscriptionRetryDelay) {
                try windowElement.subscribe(axObserver, notification)
            }
        }
    }

    func stopObserving() {
        kvObservers = []
        if let axObserver {
            CFRunLoopRemoveSource(BackgroundWork.axEventsThread.runLoop,
                                  AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
    }
}

extension DispatchQueue {
    /// Runs a throwing block, retrying after a delay while it throws.
    /// Used for AX subscriptions against apps that are still launching.
    func retrying(attempts: Int, delay: TimeInterval, _ block: @escaping () throws -> Void) {
        async { [weak self] in
            do {
                try block()
            } catch {
                guard attempts > 1 else { return }
                self?.asyncAfter(deadline: .now() + delay) {
                    self?.retrying(attempts: attempts - 1, delay: delay, block)
                }
            }
        }
    }
}
