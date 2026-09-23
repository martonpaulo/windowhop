import Foundation

/// The launch-at-login state Settings shows, read from the macOS login-item
/// registration (`LoginItem` maps `SMAppService.Status` onto it) — never the
/// requested value and never stored. The stored `launchAtLogin` preference is
/// the person's intent; this is what macOS actually holds.
public enum LoginItemStatus: Equatable, CaseIterable, Sendable {
    /// Registered and approved: WindowHop opens at login.
    case enabled
    /// Not registered.
    case disabled
    /// Registered, but macOS waits for approval in Login Items settings.
    case requiresApproval
    /// Cannot be registered from this binary (a bare `swift build` product).
    case unavailable

    /// The toggle is on whenever WindowHop is registered, including while
    /// approval is pending: turning it off is then what unregisters.
    public var isOn: Bool { self == .enabled || self == .requiresApproval }

    /// `unavailable` is only ever reported while nothing is registered, so a
    /// registration can always be removed.
    public var allowsChange: Bool { self != .unavailable }

    /// Only a pending approval has a native recovery destination.
    public var offersLoginItemsSettings: Bool { self == .requiresApproval }

    /// Shown under the toggle; nil when the toggle says everything.
    public var explanation: String? {
        switch self {
        case .enabled, .disabled:
            return nil
        case .requiresApproval:
            return "WindowHop is waiting for your approval in System Settings › General › Login Items."
        case .unavailable:
            return "Launch at login is available when WindowHop runs from the Applications folder."
        }
    }

    /// Shown when a requested change did not take effect.
    public static let changeFailedExplanation =
        "Launch at login could not be configured. Run WindowHop from the Applications folder and try again."
}

/// The outcome of a requested launch-at-login change: the status read back
/// after the call, and whether the request failed. A register call that throws
/// but leaves the item awaiting approval is not a failure.
public struct LoginItemChange: Equatable, Sendable {
    public let status: LoginItemStatus
    public let failed: Bool

    public init(status: LoginItemStatus, failed: Bool) {
        self.status = status
        self.failed = failed
    }
}
