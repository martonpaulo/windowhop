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
    public let name: String?
    public let bundleIdentifier: String?
    let executablePath: String?
    public internal(set) var isHidden: Bool
    /// A graceful Quit was already requested from the close dialog; the next quit
    /// offer escalates to a confirmed Force Quit (ported from AltTab's
    /// alreadyRequestedToQuit, with an explicit confirmation added).
    public internal(set) var quitRequested = false
    // Observer state is confined to BackgroundWork.axReadsQueue: only `handle(_:)`
    // and the work it schedules on that queue read or write these two fields
    // (tests read `lifecycle` from a block on that queue).
    private var axObserver: AXObserver?
    private(set) var lifecycle = ObserverLifecycle(maxAttempts: TrackedApp.subscriptionRetries,
                                                   retryDelay: TrackedApp.subscriptionRetryDelay)
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

    /// Reads eligibility on main, then hands a `start` to the AX reads queue, which
    /// owns the observer lifecycle.
    func observeIfEligible() {
        guard runningApplication.activationPolicy != .prohibited else { return }
        startObserving()
    }

    func startObserving() {
        BackgroundWork.axReadsQueue.async { [weak self] in
            self?.handle(.start)
        }
    }

    /// Stops observing for good: pending retries, late subscription results and
    /// window subscriptions of this app all find their generation stale afterwards.
    func stopObserving() {
        kvObservers = []
        // strong capture: the store drops the app right after this call, and the stop
        // must still run to detach the observer's run-loop source
        BackgroundWork.axReadsQueue.async {
            self.handle(.stop)
        }
    }

    // MARK: - AX reads queue only

    /// Feeds one event to the lifecycle and runs its commands. Runs on the AX reads queue.
    private func handle(_ event: ObserverLifecycle.Event) {
        dispatchPrecondition(condition: .onQueue(BackgroundWork.axReadsQueue))
        let commands = lifecycle.handle(event)
        DebugLog.log("observer pid=\(pid) \(event) -> \(lifecycle.phase) \(commands)")
        for command in commands {
            run(command)
        }
    }

    private func run(_ command: ObserverLifecycle.Command) {
        switch command {
        case let .subscribe(generation):
            handle(subscribeFirstNotification(generation: generation))
        case let .scheduleRetry(generation, delay):
            BackgroundWork.axReadsQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.handle(.retryDue(generation: generation))
            }
        case let .subscribeRemainingNotifications(generation):
            guard let axObserver else { return }
            for notification in TrackedApp.appNotifications.dropFirst() {
                subscribe(axElement, to: notification, with: axObserver, generation: generation)
            }
        case .discoverWindows:
            // the store drops the request when this app is no longer the tracked one
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                WindowStore.shared.discoverWindows(of: self)
            }
        case .removeObserver:
            if let axObserver {
                CFRunLoopRemoveSource(BackgroundWork.axEventsThread.runLoop,
                                      AXObserverGetRunLoopSource(axObserver), .commonModes)
            }
            axObserver = nil
        }
    }

    /// The first successful subscription marks the app as really finished launching
    /// (some apps report isFinishedLaunching but still return .cannotComplete);
    /// only then are its existing windows discovered.
    private func subscribeFirstNotification(generation: UInt64) -> ObserverLifecycle.Event {
        let observer: AXObserver
        if let axObserver {
            observer = axObserver
        } else {
            var created: AXObserver?
            AXObserverCreate(pid, AXNotificationRouter.axObserverCallback, &created)
            guard let created else {
                return .subscriptionFailed(generation: generation, retryable: false)
            }
            // a CFRunLoop source may be added to another thread's run loop
            CFRunLoopAddSource(BackgroundWork.axEventsThread.runLoop,
                               AXObserverGetRunLoopSource(created), .commonModes)
            axObserver = created
            observer = created
        }
        do {
            let accepted = try axElement.subscribe(observer, TrackedApp.appNotifications.first!)
            return accepted ? .subscriptionSucceeded(generation: generation)
                : .subscriptionFailed(generation: generation, retryable: false)
        } catch {
            return .subscriptionFailed(generation: generation, retryable: true)
        }
    }

    /// Adds window-level notifications for a newly discovered window element.
    /// Runs on the AX reads queue; does nothing once the app stopped being observed.
    func subscribeToWindowNotifications(_ windowElement: AXUIElement) {
        dispatchPrecondition(condition: .onQueue(BackgroundWork.axReadsQueue))
        guard case let .ready(generation) = lifecycle.phase, let axObserver else { return }
        for notification in TrackedApp.windowNotifications {
            subscribe(windowElement, to: notification, with: axObserver, generation: generation)
        }
    }

    private func subscribe(_ element: AXUIElement, to notification: String,
                           with observer: AXObserver, generation: UInt64) {
        BackgroundWork.axReadsQueue.retrying(attempts: TrackedApp.subscriptionRetries,
                                             delay: TrackedApp.subscriptionRetryDelay,
                                             isCurrent: { [weak self] in
                                                 self?.lifecycle.isCurrent(generation) ?? false
                                             }) {
            try element.subscribe(observer, notification)
        }
    }
}

extension DispatchQueue {
    /// Runs a throwing block, retrying after a delay while it throws.
    /// Used for AX subscriptions against apps that are still launching.
    /// `isCurrent` runs on this queue before each attempt; once it returns false the
    /// chain ends, so work scheduled for a stopped owner never reaches AX.
    func retrying(attempts: Int, delay: TimeInterval, isCurrent: @escaping () -> Bool,
                  _ block: @escaping () throws -> Void) {
        async { [weak self] in
            guard isCurrent() else { return }
            do {
                try block()
            } catch {
                guard attempts > 1 else { return }
                self?.asyncAfter(deadline: .now() + delay) {
                    self?.retrying(attempts: attempts - 1, delay: delay, isCurrent: isCurrent, block)
                }
            }
        }
    }
}
