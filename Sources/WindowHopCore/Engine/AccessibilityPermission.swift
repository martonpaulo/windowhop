import AppKit
import ApplicationServices

/// Accessibility is the only permission WindowHop needs: it powers the event tap,
/// window discovery, and window activation. Screen Recording is never requested.
public enum AccessibilityPermission {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt directing the user to System Settings.
    public static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Calls the handler on the main thread whenever the system's accessibility trust
    /// table changes (grant or revocation), plus once shortly after subscription.
    /// Event-driven: no polling while the app idles.
    public static func observeChanges(_ handler: @escaping (Bool) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main) { _ in
            // the trust table updates just after the notification fires
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                handler(isGranted)
            }
        }
    }
}
