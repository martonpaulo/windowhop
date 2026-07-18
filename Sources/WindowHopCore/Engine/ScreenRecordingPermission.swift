import AppKit

/// Screen Recording is needed only for the optional Window Previews appearance.
/// App Icons mode never touches it, and WindowHop never prompts until the user
/// explicitly selects Window Previews.
public enum ScreenRecordingPermission {
    public enum Status: Equatable {
        case authorized
        case notDetermined
        case denied
        /// Kept distinct in the UI/state contract even though current public
        /// macOS capture APIs report restricted access as a failed preflight.
        case restricted

        public var isAuthorized: Bool { self == .authorized }
        public var requiresPermission: Bool { !isAuthorized }
    }

    private static let requestedKey = "screenRecordingPermissionWasRequested"

    public static var status: Status {
        classify(preflightGranted: CGPreflightScreenCaptureAccess(),
                 hasRequested: UserDefaults.standard.bool(forKey: requestedKey),
                 isRestricted: false)
    }

    public static var isGranted: Bool {
        status.isAuthorized
    }

    /// Shows the system prompt (at most once per app session, per macOS rules).
    /// Returns the current grant state.
    @discardableResult
    public static func request() -> Bool {
        UserDefaults.standard.set(true, forKey: requestedKey)
        return CGRequestScreenCaptureAccess()
    }

    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Pure classification seam for permission-state regression coverage.
    /// Public macOS preflight currently collapses restricted into a failed
    /// grant; callers with a stronger public signal can preserve it here.
    static func classify(preflightGranted: Bool,
                         hasRequested: Bool,
                         isRestricted: Bool) -> Status {
        if preflightGranted { return .authorized }
        if isRestricted { return .restricted }
        return hasRequested ? .denied : .notDetermined
    }
}
