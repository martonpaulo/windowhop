import Foundation

/// Pure session state machine: semantic keyboard/mouse events in, UI commands out.
/// Runs on the main thread and knows nothing about AX or AppKit.
///
/// Phases:
/// - inactive:   no session
/// - held:       the hold-modifier is down; releasing it activates the selection
/// - sticky:     session continues after a close-confirmation dialog; the modifier is
///               no longer the anchor, so only Return/Escape/click end the session
/// - confirming: a close-confirmation dialog is open; keyboard events pass through to it
public struct SwitcherState {
    public enum Phase: Equatable {
        case inactive
        case held
        case sticky
        case confirming
    }

    public enum Command: Equatable {
        case none
        case show(selectedIndex: Int)
        case select(index: Int)
        case activate(index: Int)
        case cancel
        case requestClose(index: Int)
    }

    public private(set) var phase: Phase = .inactive
    public private(set) var selectedIndex = 0
    public private(set) var itemCount = 0

    public init() {}

    public var isActive: Bool { phase != .inactive }

    /// First trigger opens the switcher selecting the previously focused window
    /// (index 1 in MRU order); a backward trigger starts from the end. Further
    /// triggers step the selection.
    public mutating func trigger(backward: Bool, itemCount count: Int) -> Command {
        switch phase {
        case .inactive:
            guard count > 0 else { return .none }
            itemCount = count
            phase = .held
            selectedIndex = backward ? count - 1 : min(1, count - 1)
            return .show(selectedIndex: selectedIndex)
        case .held, .sticky:
            return step(backward: backward)
        case .confirming:
            return .none
        }
    }

    /// The "Open WindowHop" shortcut: opens a session that survives modifier release.
    /// Selection starts on the previously focused window, like a normal trigger.
    /// Invoking it while a session is already open keeps the current session as-is.
    public mutating func openPersistent(itemCount count: Int) -> Command {
        guard phase == .inactive else { return .none }
        guard count > 0 else { return .none }
        itemCount = count
        phase = .sticky
        selectedIndex = min(1, count - 1)
        return .show(selectedIndex: selectedIndex)
    }

    /// Space activates the selection, but only in a persistent session; during a
    /// held session Space is not a WindowHop key (⌘Space must stay Spotlight's).
    public mutating func spaceKey() -> Command {
        guard phase == .sticky else { return .none }
        return finish(.activate(index: selectedIndex))
    }

    public mutating func step(backward: Bool) -> Command {
        guard phase == .held || phase == .sticky, itemCount > 0 else { return .none }
        selectedIndex = backward
            ? (selectedIndex - 1 + itemCount) % itemCount
            : (selectedIndex + 1) % itemCount
        return .select(index: selectedIndex)
    }

    /// Releasing the last held modifier key activates the selection, but only while held.
    public mutating func modifierReleased() -> Command {
        guard phase == .held else { return .none }
        return finish(.activate(index: selectedIndex))
    }

    public mutating func escape() -> Command {
        guard phase == .held || phase == .sticky else { return .none }
        return finish(.cancel)
    }

    public mutating func returnKey() -> Command {
        guard phase == .held || phase == .sticky else { return .none }
        return finish(.activate(index: selectedIndex))
    }

    public enum ArrowDirection {
        case up, down, left, right
    }

    public mutating func arrow(_ direction: ArrowDirection) -> Command {
        switch direction {
        case .down, .right: return step(backward: false)
        case .up, .left: return step(backward: true)
        }
    }

    public mutating func deleteKey() -> Command {
        closeRequested(index: selectedIndex)
    }

    /// Close request for an explicit item (the hover close control); Delete is the
    /// same flow aimed at the current selection. The selection is left untouched so
    /// a cancelled confirmation restores exactly the previous state.
    public mutating func closeRequested(index: Int) -> Command {
        guard phase == .held || phase == .sticky,
              index >= 0, index < itemCount else { return .none }
        phase = .confirming
        return .requestClose(index: index)
    }

    /// The close-confirmation dialog was dismissed (either way); the session continues
    /// without a held modifier. List changes caused by the close arrive via listChanged.
    public mutating func confirmationFinished() -> Command {
        guard phase == .confirming else { return .none }
        phase = .sticky
        return .none
    }

    public mutating func itemClicked(index: Int) -> Command {
        guard isActive, index >= 0, index < itemCount else { return .none }
        selectedIndex = index
        return finish(.activate(index: index))
    }

    public mutating func outsideClick() -> Command {
        guard phase == .held || phase == .sticky else { return .none }
        return finish(.cancel)
    }

    /// The visible list changed while the session is open (window closed, app quit, …).
    /// Keeps a logical nearby selection; cancels when nothing is left.
    public mutating func listChanged(itemCount count: Int, preferredIndex: Int?) -> Command {
        guard isActive else { return .none }
        if count == 0 {
            return finish(.cancel)
        }
        itemCount = count
        selectedIndex = max(0, min(preferredIndex ?? selectedIndex, count - 1))
        return .select(index: selectedIndex)
    }

    /// Ends the session unconditionally (used when the engine shuts down mid-session).
    public mutating func reset() {
        phase = .inactive
        selectedIndex = 0
        itemCount = 0
    }

    private mutating func finish(_ command: Command) -> Command {
        phase = .inactive
        return command
    }
}
