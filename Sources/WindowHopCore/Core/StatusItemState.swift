import Foundation

/// What the optional menu bar item shows about WindowHop's operation, derived
/// from existing owners (`Preferences.switcherEnabled` and the Accessibility
/// grant) — never stored. Each state has its own symbol shape, so it reads
/// without color, and its own accessibility label.
public enum StatusItemState: Equatable, CaseIterable {
    case active
    case paused
    case accessibilityRequired

    /// Missing Accessibility wins over paused: enabling the switcher cannot
    /// help until access is granted.
    public static func resolve(switcherEnabled: Bool, accessibilityGranted: Bool) -> StatusItemState {
        if !accessibilityGranted { return .accessibilityRequired }
        return switcherEnabled ? .active : .paused
    }

    /// Template SF Symbol; the states differ by shape, never by color.
    public var symbolName: String {
        switch self {
        case .active: return "rectangle.on.rectangle"
        case .paused: return "rectangle.on.rectangle.slash"
        case .accessibilityRequired: return "exclamationmark.triangle"
        }
    }

    /// The item's accessibility label carries the state, not only the app name.
    public var accessibilityLabel: String {
        switch self {
        case .active: return "WindowHop"
        case .paused: return "WindowHop, paused"
        case .accessibilityRequired: return "WindowHop, Accessibility access needed"
        }
    }

    /// The disabled status row at the top of the menu; nil when nothing needs saying.
    public var statusText: String? {
        switch self {
        case .active: return nil
        case .paused: return "Paused"
        case .accessibilityRequired: return "Accessibility access needed"
        }
    }

    /// Whether the menu offers the Accessibility setup recovery command.
    public var offersAccessibilitySetup: Bool { self == .accessibilityRequired }
}
