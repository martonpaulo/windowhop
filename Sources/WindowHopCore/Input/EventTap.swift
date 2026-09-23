import AppKit
import ApplicationServices
import Synchronization
import WindowHopKit

/// Semantic input events the tap produces for the controller (delivered on main).
public enum SwitcherInputEvent: Equatable, Sendable {
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
/// mutex-protected box because the callback must decide synchronously on its own thread.
public enum TapMode: Equatable, Sendable {
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

enum EventTapDisposition: Equatable, Sendable {
    case pass
    case consume
}

struct EventTapDecision: Equatable, Sendable {
    let disposition: EventTapDisposition
    let input: SwitcherInputEvent?

    static let pass = EventTapDecision(disposition: .pass, input: nil)
    static let consume = EventTapDecision(disposition: .consume, input: nil)
}

/// Pure, lock-contained interception state. It owns the complete key sequence:
/// a keyUp remains suppressed even if the main thread already ended the
/// session after its keyDown. That prevents orphaned Tab events from reaching
/// the native switcher during rapid input or cancellation.
struct EventTapInterceptionState: Sendable {
    var mode: TapMode = .off
    var holdModifier: CGEventFlags = .maskCommand
    var persistentShortcut: PersistentShortcut?
    /// True while the Settings shortcut recorder is recording. Owned by the
    /// recorder, not the tap lifecycle, so `reset()` keeps it: while it is set,
    /// `watching` passes every key so an already-active chord reaches the
    /// recorder instead of opening a session. Fail-safe if it were stuck: only
    /// WindowHop's own chords pause, native Cmd-Tab keeps working.
    var isRecordingShortcut = false
    private(set) var suppressedKeyUps: Set<Int64> = []

    mutating func reset() {
        mode = .off
        suppressedKeyUps.removeAll()
    }

    mutating func decide(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags
    ) -> EventTapDecision {
        if type == .flagsChanged {
            guard mode == .sessionHeld, !flags.contains(holdModifier) else {
                return .pass
            }
            return EventTapDecision(disposition: .pass, input: .modifierReleased)
        }

        // A key-up is consumed only when the latest key-down of that key was. Each
        // key-down drops the key's ownership here and the branches below take it again
        // only when they consume this key-down. So a key-up missed while the tap was
        // disabled (timeout, user input, sleep) heals at the next press of that key,
        // without a timer and without a reset that would leak a held session's Tab
        // release after the re-enable.
        if type == .keyDown {
            suppressedKeyUps.remove(keyCode)
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
            guard type == .keyDown, !isRecordingShortcut else { return .pass }
            if isSwitcherTrigger(keyCode: keyCode, flags: flags) {
                mode = .sessionHeld
                suppressedKeyUps.insert(keyCode)
                return EventTapDecision(
                    disposition: .consume,
                    input: .trigger(backward: flags.contains(.maskShift)))
            }
            if let persistentShortcut,
                persistentShortcut.matches(keyCode: keyCode, flags: flags)
            {
                mode = .sessionSticky
                suppressedKeyUps.insert(keyCode)
                return EventTapDecision(disposition: .consume, input: .openPersistent)
            }
            return .pass
        case .sessionHeld, .sessionSticky:
            let sticky = mode == .sessionSticky
            if let persistentShortcut,
                persistentShortcut.matches(keyCode: keyCode, flags: flags)
            {
                if type == .keyDown { suppressedKeyUps.insert(keyCode) }
                return .consume
            }
            guard
                let input = sessionEvent(
                    for: keyCode, flags: flags, sticky: sticky)
            else { return .pass }
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

    /// Session keys match only with Shift plus the modifiers that own the
    /// session: the hold modifier in a held session, the Open WindowHop chord's
    /// modifiers in a sticky one. Any other ⌘/⌥/⌃ makes the chord someone
    /// else's, so it passes: ⌃⌥ + arrows/Space/Return/Delete are VoiceOver
    /// commands, and which session tap sees them first depends on which was
    /// created last (`headInsertEventTap`), so matching cannot rely on order.
    /// Caps Lock, Fn and the keypad flag are ignored. Two exceptions: the
    /// switcher trigger keeps stepping in any session, and ⌘, needs ⌘.
    private func sessionEvent(
        for keyCode: Int64,
        flags: CGEventFlags,
        sticky: Bool
    ) -> SwitcherInputEvent? {
        let owner = sticky ? persistentShortcut?.modifiers ?? [] : holdModifier
        let foreign = flags.intersection(Self.chordModifiers).subtracting(owner)
        if keyCode == KeyCode.comma {
            return flags.contains(.maskCommand) && foreign.subtracting(.maskCommand).isEmpty
                ? .openSettings : nil
        }
        if keyCode == KeyCode.tab, isSwitcherTrigger(keyCode: keyCode, flags: flags) {
            return .step(backward: flags.contains(.maskShift))
        }
        guard foreign.isEmpty else { return nil }
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
        default:
            return nil
        }
    }

    /// The modifiers that make a chord belong to someone; Shift never does.
    private static let chordModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]

    private func otherModifiers(than holdModifier: CGEventFlags) -> CGEventFlags {
        Self.chordModifiers.subtracting(holdModifier)
    }
}

/// A consuming CGEvent tap. AltTab disables the native Cmd-Tab symbolic hotkey with
/// the private CGSSetSymbolicHotKeyEnabled and restores it on quit; WindowHop instead
/// consumes the chord in the tap. That is inherently fail-safe: if WindowHop is
/// disabled, quits, crashes, loses permission, or the tap is silenced by Secure Input,
/// events flow again and the native macOS switcher is untouched.
@MainActor
public final class EventTap {

    /// Everything the tap thread touches, behind one lock: the interception state
    /// the callback decides with, and the port it re-enables after a timeout.
    private struct TapThreadState {
        var interception = EventTapInterceptionState()
        var eventTap: TapPort?
    }

    /// The tap's mach port, shared between main (start/stop/re-arm) and the tap
    /// thread (re-enable after a timeout).
    ///
    /// `@unchecked Sendable` invariant: the port is an immutable CF reference whose
    /// retain/release is atomic, and `CGEvent.tapEnable`/`tapIsEnabled` are safe to
    /// call from any thread (the tap thread re-enables it by design); the mutable
    /// slot holding it is guarded by `tapThreadState`'s mutex.
    private struct TapPort: @unchecked Sendable {
        let port: CFMachPort
    }

    private nonisolated let tapThreadState = Mutex(TapThreadState())
    /// The run-loop source only main touches (start/stop).
    private var runLoopSource: CFRunLoopSource?

    /// Called on the main queue with each semantic event.
    public var onEvent: ((SwitcherInputEvent) -> Void)?

    /// Owned by `AppDelegate` for the whole process, which is what makes the
    /// unretained `userInfo` pointer the C callback receives sound.
    public init() {}

    public var mode: TapMode {
        get { tapThreadState.withLock { $0.interception.mode } }
        set { tapThreadState.withLock { $0.interception.mode = newValue } }
    }

    public var holdModifier: CGEventFlags {
        get { tapThreadState.withLock { $0.interception.holdModifier } }
        set { tapThreadState.withLock { $0.interception.holdModifier = newValue } }
    }

    /// The optional "Open WindowHop" chord; nil when unassigned.
    public var persistentShortcut: PersistentShortcut? {
        get { tapThreadState.withLock { $0.interception.persistentShortcut } }
        set { tapThreadState.withLock { $0.interception.persistentShortcut = newValue } }
    }

    /// Set while the Settings shortcut recorder is recording; see
    /// `EventTapInterceptionState.isRecordingShortcut`. `stop()` keeps it.
    public var isRecordingShortcut: Bool {
        get { tapThreadState.withLock { $0.interception.isRecordingShortcut } }
        set { tapThreadState.withLock { $0.interception.isRecordingShortcut = newValue } }
    }

    /// Creates the tap on the dedicated tap thread. Returns false when tap creation
    /// fails (no Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        if let eventTap = tapThreadState.withLock({ $0.eventTap?.port }) {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return true
        }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        // The C callback captures nothing: it reaches the tap through `userInfo`.
        // Unretained is safe because `AppDelegate` owns this instance for the whole
        // process.
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        tapThreadState.withLock { $0.eventTap = TapPort(port: tap) }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(BackgroundWork.eventTapThread.runLoop, source, .commonModes)
        return true
    }

    public func stop() {
        let eventTap = tapThreadState.withLock { state in
            defer {
                state.eventTap = nil
                state.interception.reset()
            }
            return state.eventTap
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap.port, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(BackgroundWork.eventTapThread.runLoop, runLoopSource, .commonModes)
            }
        }
        runLoopSource = nil
    }

    /// macOS silently disables taps after sleep/wake or long stalls without sending
    /// tapDisabled events; callers re-arm on wake and unlock notifications.
    public func reEnableIfNeeded() {
        guard let eventTap = tapThreadState.withLock({ $0.eventTap?.port }),
            !CGEvent.tapIsEnabled(tap: eventTap)
        else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    // MARK: - Callback (runs on the tap thread; must stay small and non-blocking)

    /// Both disable notices re-enable the tap. The interception state is kept on
    /// purpose: a held session stays owned, and a key-up missed while the tap was
    /// off heals at the next key-down of that key (`EventTapInterceptionState.decide`).
    nonisolated static func reEnablesTap(after type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    fileprivate nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if Self.reEnablesTap(after: type) {
            if let eventTap = tapThreadState.withLock({ $0.eventTap?.port }) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let decision = tapThreadState.withLock {
            $0.interception.decide(type: type, keyCode: keyCode, flags: flags)
        }
        if let input = decision.input {
            post(input)
        }
        return decision.disposition == .consume
            ? nil
            : Unmanaged.passUnretained(event)
    }

    private nonisolated func post(_ inputEvent: SwitcherInputEvent) {
        let postedAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            // Logged here on main, not in `handle`: the tap callback only decides and posts.
            let hopMs = (CFAbsoluteTimeGetCurrent() - postedAt) * 1000
            Log.input.debug(
                """
                tap: consumed \(String(describing: inputEvent), privacy: .public) \
                (+\(hopMs, format: .fixed(precision: 2), privacy: .public)ms hop)
                """)
            self?.onEvent?(inputEvent)
        }
    }
}

/// The tap's C callback runs on the event-tap thread. It is a file-scope constant, not a
/// closure written inside the `@MainActor` class: Swift 6 would give such a closure the
/// class's isolation and trap on the tap thread at the first key event.
let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        .handle(type: type, event: event)
}
