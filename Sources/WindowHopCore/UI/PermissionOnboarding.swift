import AppKit
import SwiftUI

/// First-run explanation of the single permission WindowHop needs.
/// Polls only while this window is visible; closes itself once access is granted.
public final class PermissionOnboardingController {
    public static let shared = PermissionOnboardingController()

    private var window: NSWindow?
    private var pollTimer: Timer?
    public var onGranted: (() -> Void)?

    public func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionOnboardingView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Welcome to WindowHop"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        AccessibilityPermission.prompt()
        startPolling()
    }

    public func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
    }

    /// Bounded polling: only while the onboarding window is on screen, because
    /// macOS offers no callback usable before the permission is first granted.
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.window?.isVisible != true {
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                return
            }
            if AccessibilityPermission.isGranted {
                self.close()
                self.onGranted?()
            }
        }
    }
}

struct PermissionOnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            Text("WindowHop needs Accessibility access")
                .font(.title3.weight(.semibold))
            Text("macOS requires this permission to list your windows and to switch between them with the keyboard. WindowHop uses no other permission — it never records your screen and never connects to the network.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                AccessibilityPermission.openSystemSettings()
            }
            .keyboardShortcut(.defaultAction)
            Text("System Settings → Privacy & Security → Accessibility → enable WindowHop")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 460)
    }
}
