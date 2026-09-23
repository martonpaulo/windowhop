import Foundation

/// When window activation falls back to making the whole application frontmost.
///
/// Activating a window raises it, then asks its app to activate. That request is
/// cooperative and macOS can refuse it; the permission-backed AX frontmost
/// attribute always works but fronts every window of the app on every display,
/// which is the bug in #41. So the fall-back runs only when, after a short wait,
/// another app still holds focus.
public enum ActivationFallback {
    /// How long activation gets before the fall-back is considered. The probe for
    /// #41 measured the switch complete within 50 ms; this leaves room for a
    /// busy app without a visible delay.
    public static let delay: DispatchTimeInterval = .milliseconds(150)

    /// True when the target app is not the focused one. An unknown focus (the
    /// system-wide read failed) counts as not focused, so the switch still happens.
    public static func isNeeded(focusedPID: pid_t?, targetPID: pid_t) -> Bool {
        focusedPID != targetPID
    }
}
