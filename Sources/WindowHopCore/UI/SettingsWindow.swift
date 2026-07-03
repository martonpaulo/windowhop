import AppKit
import SwiftUI

/// The Settings window: only implemented, useful options.
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// The settings UI, also used by the debug render harness.
    public static func makeContentViewController() -> NSViewController {
        NSHostingController(rootView: SettingsView())
    }

    public func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: Self.makeContentViewController())
            newWindow.title = "WindowHop Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.Key.switcherEnabled.rawValue) private var switcherEnabled = true
    @AppStorage(Preferences.Key.shortcut.rawValue) private var shortcut = ShortcutSpec.commandTab.rawValue
    @AppStorage(Preferences.Key.includeOtherSpaces.rawValue) private var includeOtherSpaces = true
    @AppStorage(Preferences.Key.includeOtherDisplays.rawValue) private var includeOtherDisplays = true
    @AppStorage(Preferences.Key.showTabCounts.rawValue) private var showTabCounts = true
    @AppStorage(Preferences.Key.showMenuBarItem.rawValue) private var showMenuBarItem = false
    @AppStorage(Preferences.Key.showDockIcon.rawValue) private var showDockIcon = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginFailed = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable WindowHop", isOn: $switcherEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        let succeeded = LoginItem.set(newValue)
                        launchAtLoginFailed = !succeeded
                        if succeeded {
                            Preferences.shared.launchAtLogin = newValue
                        } else {
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if launchAtLoginFailed {
                    Text("Launch at login could not be configured. Run WindowHop from the Applications folder and try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Picker("Switcher shortcut", selection: $shortcut) {
                    ForEach(ShortcutSpec.allCases) { spec in
                        Text(spec.displayName).tag(spec.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Hold the modifier and press Tab to cycle forward; add Shift to cycle backward. Releasing the modifier switches to the selected window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Include windows from other Spaces", isOn: $includeOtherSpaces)
                Toggle("Include windows from other displays", isOn: $includeOtherDisplays)
                Toggle("Show tab counts", isOn: $showTabCounts)
            }
            Section("Appearance") {
                Toggle("Show menu bar item", isOn: $showMenuBarItem)
                Toggle("Show Dock icon", isOn: $showDockIcon)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
