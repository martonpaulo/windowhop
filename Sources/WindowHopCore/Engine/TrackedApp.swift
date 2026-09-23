import AppKit
import ApplicationServices
import WindowHopKit

/// One running application we observe, ported from AltTab v10.12.0's Application.
/// A single AXObserver per app carries both app-level and window-level notifications;
/// it lives in `observer`, an actor isolated to the AX reads queue.
@MainActor
public final class TrackedApp {
    public nonisolated let runningApplication: NSRunningApplication
    public nonisolated let pid: pid_t
    public nonisolated let axElement: AXUIElement
    public nonisolated let name: String?
    public nonisolated let bundleIdentifier: String?
    nonisolated let executablePath: String?
    /// Owns the AXObserver and its subscription lifecycle, off main.
    nonisolated let observer: AppObserver
    public internal(set) var isHidden: Bool
    /// A graceful Quit was already requested from the close dialog; the next quit
    /// offer escalates to a confirmed Force Quit (ported from AltTab's
    /// alreadyRequestedToQuit, with an explicit confirmation added).
    public internal(set) var quitRequested = false
    private var kvObservers: [NSKeyValueObservation] = []
    private var cachedIcon: NSImage?

    init(_ runningApplication: NSRunningApplication, router: AXNotificationRouter) {
        self.runningApplication = runningApplication
        pid = runningApplication.processIdentifier
        axElement = AXUIElementCreateApplication(pid)
        observer = AppObserver(pid: pid, axElement: axElement, router: router)
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

    nonisolated func windowFacts(from attributes: AXAttributes) -> WindowFacts {
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
        observer.enqueue(.start)
    }

    /// Stops observing for good: pending retries, late subscription results and
    /// window subscriptions of this app all find their generation stale afterwards.
    /// The queued stop holds the observer strongly, so it still runs (and detaches
    /// the run-loop source) after the store drops this app.
    func stopObserving() {
        kvObservers = []
        observer.enqueue(.stop)
    }
}

/// One app's AXObserver and its `ObserverLifecycle`, the state #61 serialized.
/// The actor's executor is `BackgroundWork.axReadsQueue`: main queues events on that
/// queue in FIFO order and each block enters the actor synchronously
/// (`assumeIsolated`), so a `start` followed by a `stop` can never be reordered the
/// way two unstructured `Task`s could.
actor AppObserver {
    private static let appNotifications = [
        kAXApplicationActivatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]
    private static let subscriptionRetries = 30
    private static let subscriptionRetryDelay = 0.5

    nonisolated let pid: pid_t
    private nonisolated let axElement: AXUIElement
    /// Held strongly: the AXObserver's notifications carry it as an unretained
    /// `refcon`, so it must outlive `axObserver`.
    private nonisolated let router: AXNotificationRouter
    private var axObserver: AXObserver?
    private(set) var lifecycle = ObserverLifecycle(maxAttempts: AppObserver.subscriptionRetries,
                                                   retryDelay: AppObserver.subscriptionRetryDelay)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        BackgroundWork.axReadsQueue.asUnownedSerialExecutor()
    }

    init(pid: pid_t, axElement: AXUIElement, router: AXNotificationRouter) {
        self.pid = pid
        self.axElement = axElement
        self.router = router
    }

    /// Queues one lifecycle event behind the AX reads already scheduled.
    nonisolated func enqueue(_ event: ObserverLifecycle.Event) {
        BackgroundWork.axReadsQueue.async {
            self.assumeIsolated { $0.handle(event) }
        }
    }

    /// Feeds one event to the lifecycle and runs its commands.
    private func handle(_ event: ObserverLifecycle.Event) {
        let commands = lifecycle.handle(event)
        Log.windows.debug("""
            observer pid=\(self.pid, privacy: .public) \(String(describing: event), privacy: .public) \
            -> \(String(describing: self.lifecycle.phase), privacy: .public) \
            \(String(describing: commands), privacy: .public)
            """)
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
                self?.assumeIsolated { $0.handle(.retryDue(generation: generation)) }
            }
        case let .subscribeRemainingNotifications(generation):
            for notification in AppObserver.appNotifications.dropFirst() {
                subscribe(axElement, to: notification, generation: generation,
                          attemptsLeft: AppObserver.subscriptionRetries)
            }
        case .discoverWindows:
            // the store drops the request when this app is no longer the tracked one
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.router.store?.discoverWindows(of: self)
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
            let accepted = try axElement.subscribe(observer, AppObserver.appNotifications.first!,
                                                   refcon: router.refcon)
            return accepted ? .subscriptionSucceeded(generation: generation)
                : .subscriptionFailed(generation: generation, retryable: false)
        } catch {
            return .subscriptionFailed(generation: generation, retryable: true)
        }
    }

    /// Queues the window-level subscriptions for a newly discovered window element.
    nonisolated func enqueueWindowSubscription(_ windowElement: AXUIElement) {
        BackgroundWork.axReadsQueue.async {
            self.assumeIsolated { $0.subscribeToWindowNotifications(windowElement) }
        }
    }

    /// Adds window-level notifications for a newly discovered window element.
    /// Does nothing once the app stopped being observed.
    private func subscribeToWindowNotifications(_ windowElement: AXUIElement) {
        guard case let .ready(generation) = lifecycle.phase else { return }
        for notification in AppObserver.windowNotifications {
            subscribe(windowElement, to: notification, generation: generation,
                      attemptsLeft: AppObserver.subscriptionRetries)
        }
    }

    /// Subscribes, retrying after a delay while the app is unresponsive (still
    /// launching). Each attempt first checks the generation, so work scheduled for a
    /// stopped owner never reaches AX.
    private func subscribe(_ element: AXUIElement, to notification: String,
                           generation: UInt64, attemptsLeft: Int) {
        guard lifecycle.isCurrent(generation), let axObserver else { return }
        do {
            try element.subscribe(axObserver, notification, refcon: router.refcon)
        } catch {
            guard attemptsLeft > 1 else { return }
            BackgroundWork.axReadsQueue.asyncAfter(
                deadline: .now() + AppObserver.subscriptionRetryDelay) { [weak self] in
                self?.assumeIsolated {
                    $0.subscribe(element, to: notification, generation: generation,
                                 attemptsLeft: attemptsLeft - 1)
                }
            }
        }
    }
}
