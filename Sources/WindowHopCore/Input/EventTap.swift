import AppKit
import ApplicationServices

/// Semantic input events the tap produces for the controller (delivered on main).
public enum SwitcherInputEvent: Equatable {
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
public enum TapMode: Equatable {
    /// switcher disabled or permission missing: consume nothing, native Cmd-Tab works
    case off
    /// idle: consume only the two configured trigger chords
    case watching
    /// hold-based session: consume the handled keys; modifier release ends it
    case sessionHeld
    /// persistent session: like sessionHeld, but modifier release is meaningless
    /// and Space also activates
    case sessionSticky
    /// close-confirmation dialog open: consume nothing so the dialog gets the keyboard
    case passthrough
}

enum EventTapDisposition: Equatable {
    case pass
    case consume
}

struct EventTapDecision: Equatable {
    let disposition: EventTapDisposition
    let input: SwitcherInputEvent?

    static let pass = EventTapDecision(disposition: .pass, input: nil)
    static let consume = EventTapDecision(disposition: .consume, input: nil)
}

/// Pure, lock-contained interception state. It owns the complete key sequence:
/// a keyUp remains suppressed even if the main thread already ended the
/// session after its keyDown. That prevents orphaned Tab events from reaching
/// the native switcher during rapid input or cancellation.
struct EventTapInterceptionState {
    var mode: TapMode = .off
    var holdModifier: CGEventFlags = .maskCommand
    var persistentShortcut: PersistentShortcut?
    private(set) var suppressedKeyUps: Set<Int64> = []

    mutating func reset() {
        mode = .off
        suppressedKeyUps.removeAll()
    }

    mutating func decide(type: CGEventType,
                         keyCode: Int64,
                         flags: CGEventFlags) -> EventTapDecision {
        if type == .flagsChanged {
            guard mode == .sessionHeld, !flags.contains(holdModifier) else {
                return .pass
            }
            return EventTapDecision(disposition: .pass, input: .modifierReleased)
        }

        // Consume the matching release even when the controller moved back to
        // watching between the down/up halves of a rapid chord.
        if type == .keyUp, suppressedKeyUps.remove(keyCode) != nil {
            return .consume
        }

        switch mode {
        case .off, .passthrough:
            return .pass
        case .watching:
            guard type == .keyDown else { return .pass }
            if isSwitcherTrigger(keyCode: keyCode, flags: flags) {
                mode = .sessionHeld
                suppressedKeyUps.insert(keyCode)
                return EventTapDecision(
                    disposition: .consume,
                    input: .trigger(backward: flags.contains(.maskShift)))
            }
            if let persistentShortcut,
               persistentShortcut.matches(keyCode: keyCode, flags: flags) {
                mode = .sessionSticky
                suppressedKeyUps.insert(keyCode)
                return EventTapDecision(disposition: .consume, input: .openPersistent)
            }
            return .pass
        case .sessionHeld, .sessionSticky:
            let sticky = mode == .sessionSticky
            if let persistentShortcut,
               persistentShortcut.matches(keyCode: keyCode, flags: flags) {
                if type == .keyDown { suppressedKeyUps.insert(keyCode) }
                return .consume
            }
            guard let input = sessionEvent(
                for: keyCode, flags: flags, sticky: sticky) else { return .pass }
            if type == .keyDown {
                suppressedKeyUps.insert(keyCode)
                return EventTapDecision(disposition: .consume, input: input)
            }
            return type == .keyUp ? .consume : .pass
        }
    }

    private func isSwitcherTrigger(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == KeyCode.tab
            && flags.contains(holdModifier)
            && flags.isDisjoint(with: otherModifiers(than: holdModifier))
    }

    private func sessionEvent(for keyCode: Int64,
                              flags: CGEventFlags,
                              sticky: Bool) -> SwitcherInputEvent? {
        switch keyCode {
        case KeyCode.tab:
            return .step(backward: flags.contains(.maskShift))
        case KeyCode.escape:
            return .escape
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return .returnKey
        case KeyCode.space where sticky:
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
    private var interception = EventTapInterceptionState()

    /// Called on the main queue with each semantic event.
    public var onEvent: ((SwitcherInputEvent) -> Void)?

    public var mode: TapMode {
        get { lock.lock(); defer { lock.unlock() }; return interception.mode }
        set { lock.lock(); interception.mode = newValue; lock.unlock() }
    }

    public var holdModifier: CGEventFlags {
        get { lock.lock(); defer { lock.unlock() }; return interception.holdModifier }
        set { lock.lock(); interception.holdModifier = newValue; lock.unlock() }
    }

    /// The optional "Open WindowHop" chord; nil when unassigned.
    public var persistentShortcut: PersistentShortcut? {
        get { lock.lock(); defer { lock.unlock() }; return interception.persistentShortcut }
        set { lock.lock(); interception.persistentShortcut = newValue; lock.unlock() }
    }

    /// Creates the tap on the dedicated tap thread. Returns false when tap creation
    /// fails (no Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        if let eventTap {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return true
        }
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
        lock.lock()
        interception.reset()
        lock.unlock()
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
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        lock.lock()
        let decision = interception.decide(type: type, keyCode: keyCode, flags: event.flags)
        lock.unlock()
        if let input = decision.input {
            DebugLog.log("tap: consumed \(input)")
            post(input)
        }
        return decision.disposition == .consume
            ? nil
            : Unmanaged.passUnretained(event)
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
