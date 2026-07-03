import AppKit

/// Dedicated threads and queues, trimmed from AltTab's BackgroundWork.
/// AX observers and the event tap each get a thread with a live CFRunLoop so their
/// callbacks never contend with the main thread; AX reads/writes go through serial
/// queues so a beach-balling app can never stall the UI or the input callback.
public enum BackgroundWork {
    /// Hosts every AXObserver's run-loop source.
    public static let axEventsThread = RunLoopThread(name: "windowhop.ax-events")
    /// Hosts the CGEvent tap's run-loop source.
    public static let eventTapThread = RunLoopThread(name: "windowhop.event-tap")
    /// All AX attribute reads and discovery work.
    public static let axReadsQueue = DispatchQueue(label: "windowhop.ax-reads", qos: .userInteractive)
    /// AX actions (raise, close, de-fullscreen) so they can't block reads or the UI.
    public static let axActionsQueue = DispatchQueue(label: "windowhop.ax-actions", qos: .userInteractive)

    public static func start() {
        _ = axEventsThread.runLoop
        _ = eventTapThread.runLoop
    }
}

/// A thread that runs a CFRunLoop forever, so CFMachPort/AXObserver sources can live off-main.
public final class RunLoopThread {
    private let readySemaphore = DispatchSemaphore(value: 0)
    private var _runLoop: CFRunLoop!

    public var runLoop: CFRunLoop { _runLoop }

    init(name: String) {
        let thread = Thread { [weak self] in
            self?._runLoop = CFRunLoopGetCurrent()
            self?.readySemaphore.signal()
            // keep the run loop alive with a port source; CFRunLoopRun exits without sources
            var context = CFRunLoopSourceContext()
            let source = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        readySemaphore.wait()
    }
}
