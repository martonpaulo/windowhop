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
        // the Settings window is a normal switcher entry while open (the one
        // sanctioned exception to the own-window exclusion)
        if let window {
            WindowStore.shared.registerOwnWindow(window)
        }
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
    @State private var persistentShortcut = Preferences.shared.persistentShortcut
    @State private var shortcutValidationMessage: String?
    @State private var automaticUpdates = UpdateManager.shared.automaticallyChecksForUpdates

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
            }
            Section {
                Picker("Switcher shortcut", selection: $shortcut) {
                    ForEach(ShortcutSpec.allCases) { spec in
                        Text(spec.displayName).tag(spec.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: shortcut) { _, newValue in
                    // a switcher-shortcut change can invalidate the persistent chord
                    let spec = ShortcutSpec(rawValue: newValue) ?? .commandTab
                    if let current = persistentShortcut, let error = current.validate(against: spec) {
                        persistentShortcut = nil
                        shortcutValidationMessage = error.explanation
                    }
                }
                LabeledContent("Open WindowHop") {
                    ShortcutRecorderField(shortcut: $persistentShortcut,
                                          validationMessage: $shortcutValidationMessage,
                                          switcherShortcut: ShortcutSpec(rawValue: shortcut) ?? .commandTab)
                }
                .onChange(of: persistentShortcut) { _, newValue in
                    Preferences.shared.persistentShortcut = newValue
                }
                if let shortcutValidationMessage {
                    Text(shortcutValidationMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("The switcher shortcut cycles while you hold the modifier; releasing it switches windows. Open WindowHop keeps the switcher open without holding anything: Tab or arrows navigate, Return or Space switches, Escape cancels.")
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
            Section {
                Toggle("Automatically check for updates", isOn: $automaticUpdates)
                    .onChange(of: automaticUpdates) { _, newValue in
                        UpdateManager.shared.automaticallyChecksForUpdates = newValue
                    }
                    .disabled(!UpdateManager.shared.isAvailable)
                LabeledContent("Version \(UpdateManager.shared.currentVersion)") {
                    Button("Check for Updates…") {
                        UpdateManager.shared.checkForUpdates()
                    }
                    .disabled(!UpdateManager.shared.isAvailable)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Update checks against GitHub are WindowHop's only network activity. No telemetry, no accounts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
