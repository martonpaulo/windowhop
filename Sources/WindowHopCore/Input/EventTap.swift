import AppKit
import ApplicationServices

/// Semantic input events the tap produces for the controller (delivered on main).
public enum SwitcherInputEvent {
    case trigger(backward: Bool)
    case openPersistent
    case step(backward: Bool)
    case modifierReleased
    case escape
    case returnKey
    case spaceKey
    case arrow(SwitcherState.ArrowDirection)
    case deleteKey
    case openSettings
}

/// What the tap callback is allowed to consume right now. Kept in a tiny
/// lock-protected box because the callback must decide synchronously on its own thread.
public enum TapMode {
    /// switcher disabled or permission missing: consume nothing, native Cmd-Tab works
    case off
    /// idle: consume only the trigger chords when at least one window is eligible
    case watching
    /// hold-based session: consume the handled keys; modifier release ends it
    case sessionHeld
    /// persistent session: like sessionHeld, but modifier release is meaningless
    /// and Space also activates
    case sessionSticky
    /// close-confirmation dialog open: consume nothing so the dialog gets the keyboard
    case passthrough
}

/// A consuming CGEvent tap. AltTab disables the native Cmd-Tab symbolic hotkey with
/// the private CGSSetSymbolicHotKeyEnabled and restores it on quit; WindowHop instead
/// consumes the chord in the tap. That is inherently fail-safe: if WindowHop is
/// disabled, quits, crashes, loses permission, or the tap is silenced by Secure Input,
/// events flow again and the native macOS switcher is untouched.
public final class EventTap {
    public static let shared = EventTap()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let lock = NSLock()
    private var _mode: TapMode = .off
    private var _holdModifier: CGEventFlags = .maskCommand
    private var _persistentShortcut: PersistentShortcut?
    private var _eligibleCount = 0

    /// Called on the main queue with each semantic event.
    public var onEvent: ((SwitcherInputEvent) -> Void)?

    public var mode: TapMode {
        get { lock.lock(); defer { lock.unlock() }; return _mode }
        set { lock.lock(); _mode = newValue; lock.unlock() }
    }

    public var holdModifier: CGEventFlags {
        get { lock.lock(); defer { lock.unlock() }; return _holdModifier }
        set { lock.lock(); _holdModifier = newValue; lock.unlock() }
    }

    /// The optional "Open WindowHop" chord; nil when unassigned.
    public var persistentShortcut: PersistentShortcut? {
        get { lock.lock(); defer { lock.unlock() }; return _persistentShortcut }
        set { lock.lock(); _persistentShortcut = newValue; lock.unlock() }
    }

    /// Snapshot of how many windows the switcher would show; when 0 the trigger is
    /// passed through so the native switcher handles it instead of a dead chord.
    public var eligibleCount: Int {
        get { lock.lock(); defer { lock.unlock() }; return _eligibleCount }
        set { lock.lock(); _eligibleCount = newValue; lock.unlock() }
    }

    /// Creates the tap on the dedicated tap thread. Returns false when tap creation
    /// fails (no Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in EventTap.shared.handle(type: type, event: event) },
            userInfo: nil) else { return false }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(BackgroundWork.eventTapThread.runLoop, source, .commonModes)
        return true
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(BackgroundWork.eventTapThread.runLoop, runLoopSource, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        mode = .off
    }

    /// macOS silently disables taps after sleep/wake or long stalls without sending
    /// tapDisabled events; callers re-arm on wake and unlock notifications.
    public func reEnableIfNeeded() {
        guard let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    // MARK: - Callback (runs on the tap thread; must stay small and non-blocking)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let mode = _mode
        let holdModifier = _holdModifier
        let persistentShortcut = _persistentShortcut
        let eligibleCount = _eligibleCount
        lock.unlock()
        switch mode {
        case .off, .passthrough:
            return Unmanaged.passUnretained(event)
        case .watching:
            return handleWhileWatching(type, event, holdModifier, persistentShortcut, eligibleCount)
        case .sessionHeld, .sessionSticky:
            return handleDuringSession(type, event, holdModifier, persistentShortcut,
                                       sticky: mode == .sessionSticky)
        }
    }

    private func handleWhileWatching(_ type: CGEventType, _ event: CGEvent,
                                     _ holdModifier: CGEventFlags,
                                     _ persistentShortcut: PersistentShortcut?,
                                     _ eligibleCount: Int) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == KeyCode.tab,
           event.flags.contains(holdModifier),
           // only Shift may accompany the chord; Cmd-Opt-Tab etc. stay native
           event.flags.isDisjoint(with: otherModifiers(than: holdModifier)) {
            guard eligibleCount > 0 else {
                // nothing to show: let the native switcher handle the chord
                DebugLog.log("tap: trigger passed through, eligibleCount=0")
                return Unmanaged.passUnretained(event)
            }
            // flip synchronously so the very next event is treated as in-session
            mode = .sessionHeld
            let backward = event.flags.contains(.maskShift)
            DebugLog.log("tap: consumed trigger (backward=\(backward), eligible=\(eligibleCount))")
            post(.trigger(backward: backward))
            return nil
        }
        if let persistentShortcut, persistentShortcut.matches(keyCode: keyCode, flags: event.flags) {
            guard eligibleCount > 0 else { return Unmanaged.passUnretained(event) }
            mode = .sessionSticky
            DebugLog.log("tap: consumed persistent shortcut (eligible=\(eligibleCount))")
            post(.openPersistent)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleDuringSession(_ type: CGEventType, _ event: CGEvent,
                                     _ holdModifier: CGEventFlags,
                                     _ persistentShortcut: PersistentShortcut?,
                                     sticky: Bool) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            // never consume flagsChanged: swallowing modifier state breaks other apps.
            // covers left+right modifier keys: the flag clears when the last one lifts
            if !sticky, !event.flags.contains(holdModifier) {
                post(.modifierReleased)
            }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // re-invoking "Open WindowHop" during a session keeps it open (and never leaks
        // the chord to the frontmost app)
        if let persistentShortcut, persistentShortcut.matches(keyCode: keyCode, flags: event.flags) {
            return nil
        }
        guard let handled = sessionEvent(for: keyCode, flags: event.flags, sticky: sticky) else {
            // unhandled keys pass through; the switcher adds no hidden key commands
            return Unmanaged.passUnretained(event)
        }
        // consume both keyDown and keyUp of handled keys so apps never see halves
        if type == .keyDown {
            post(handled)
        }
        return nil
    }

    private func sessionEvent(for keyCode: Int64, flags: CGEventFlags, sticky: Bool) -> SwitcherInputEvent? {
        switch keyCode {
        case KeyCode.tab:
            return .step(backward: flags.contains(.maskShift))
        case KeyCode.escape:
            return .escape
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return .returnKey
        case KeyCode.space where sticky:
            // in a held session ⌘Space must stay Spotlight's; in a persistent one
            // Space activates like Return
            return .spaceKey
        case KeyCode.upArrow:
            return .arrow(.up)
        case KeyCode.downArrow:
            return .arrow(.down)
        case KeyCode.leftArrow:
            return .arrow(.left)
        case KeyCode.rightArrow:
            return .arrow(.right)
        case KeyCode.delete, KeyCode.forwardDelete:
            return .deleteKey
        case KeyCode.comma where flags.contains(.maskCommand):
            // the standard ⌘, affordance while the switcher is open
            return .openSettings
        default:
            return nil
        }
    }

    private func otherModifiers(than holdModifier: CGEventFlags) -> CGEventFlags {
        var others: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        others.remove(holdModifier)
        return others
    }

    private func post(_ inputEvent: SwitcherInputEvent) {
        let postedAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            DebugLog.log("input \(inputEvent) (+\(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - postedAt) * 1000))ms hop)")
            self?.onEvent?(inputEvent)
        }
    }
}

/// Prints diagnostics when WINDOWHOP_DEBUG=1; inert otherwise.
public enum DebugLog {
    public static let enabled = ProcessInfo.processInfo.environment["WINDOWHOP_DEBUG"] == "1"

    public static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[\(String(format: "%.3f", CFAbsoluteTimeGetCurrent()))] \(message())")
        fflush(stdout)
    }
}
