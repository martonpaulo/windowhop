import AppKit

/// Screen Recording is needed only for the optional Window Previews appearance.
/// App Icons mode never touches it, and WindowHop never prompts until the user
/// explicitly selects Window Previews.
public enum ScreenRecordingPermission {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt (at most once per app session, per macOS rules).
    /// Returns the current grant state.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
