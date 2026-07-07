import AppKit
import SwiftUI

/// The Settings window: a native multi-pane layout (toolbar-style
/// NSTabViewController, exactly like classic System Settings panes) hosting
/// SwiftUI content. Panes: General, Appearance, Updates, About.
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()

    /// The switcher-entry title; the window's visible title follows the pane name.
    public static let switcherEntryTitle = "WindowHop Settings"

    private var window: NSWindow?

    /// The settings UI, also used by the debug render harness.
    public static func makeContentViewController() -> NSViewController {
        SettingsTabViewController()
    }

    /// Individual panes for the render harness (the toolbar lives on the window
    /// and cannot be rasterized offscreen).
    public static func makePaneViewControllers() -> [(name: String, viewController: NSViewController)] {
        [
            ("general", NSHostingController(rootView: GeneralPane())),
            ("appearance", NSHostingController(rootView: AppearancePane())),
            ("updates", NSHostingController(rootView: UpdatesPane())),
            ("about", NSHostingController(rootView: AboutPane())),
        ]
    }

    public func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: Self.makeContentViewController())
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

/// Toolbar-style panes with SF Symbols; the selected pane persists across launches.
final class SettingsTabViewController: NSTabViewController {
    private static let selectedPaneKey = "settingsSelectedPane"

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // no crossfade/slide: pane switches are instant (Reduce Motion friendly)
        transitionOptions = []
        addPane(title: "General", symbol: "gearshape", view: GeneralPane())
        addPane(title: "Appearance", symbol: "rectangle.grid.1x2", view: AppearancePane())
        addPane(title: "Updates", symbol: "arrow.triangle.2.circlepath", view: UpdatesPane())
        addPane(title: "About", symbol: "info.circle", view: AboutPane())
        let saved = UserDefaults.standard.integer(forKey: Self.selectedPaneKey)
        if saved >= 0, saved < tabViewItems.count {
            selectedTabViewItemIndex = saved
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func addPane(title: String, symbol: String, view: some View) {
        let hosting = NSHostingController(rootView: AnyView(view))
        hosting.title = title
        hosting.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: hosting)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.selectedPaneKey)
    }
}

private let paneWidth: CGFloat = 560

// MARK: - General

struct GeneralPane: View {
    @AppStorage(Preferences.Key.switcherEnabled.rawValue) private var switcherEnabled = true
    @AppStorage(Preferences.Key.shortcut.rawValue) private var shortcut = ShortcutSpec.commandTab.rawValue
    @AppStorage(Preferences.Key.includeOtherSpaces.rawValue) private var includeOtherSpaces = true
    @AppStorage(Preferences.Key.includeOtherDisplays.rawValue) private var includeOtherDisplays = true
    @AppStorage(Preferences.Key.showMenuBarItem.rawValue) private var showMenuBarItem = false
    @AppStorage(Preferences.Key.showDockIcon.rawValue) private var showDockIcon = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginFailed = false
    @State private var persistentShortcut = Preferences.shared.persistentShortcut
    @State private var shortcutValidationMessage: String?
    @State private var quitConfirmationShown = false

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
                Text("The switcher shortcut cycles while you hold the modifier (add ⇧ to go backward); releasing it switches windows. Open WindowHop keeps the switcher open without holding anything: ⇥ and arrows navigate, ↩ or Space switches, ⎋ cancels, ⌫ closes a window after confirmation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Include windows from other Spaces", isOn: $includeOtherSpaces)
                Toggle("Include windows from other displays", isOn: $includeOtherDisplays)
            }
            Section {
                Toggle("Show menu bar item", isOn: $showMenuBarItem)
                Toggle("Show Dock icon", isOn: $showDockIcon)
            }
            Section {
                // macOS Form buttons ignore the destructive role's tint; make the
                // destructive intent visible explicitly
                Button(role: .destructive) {
                    quitConfirmationShown = true
                } label: {
                    Text("Quit WindowHop…")
                        .foregroundStyle(.red)
                }
                .confirmationDialog("Quit WindowHop?",
                                    isPresented: $quitConfirmationShown) {
                    Button("Quit WindowHop", role: .destructive) {
                        NSApp.terminate(nil)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The native ⌘⇥ app switcher takes over until you open WindowHop again.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize()
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @AppStorage(Preferences.Key.appearanceMode.rawValue) private var appearanceMode = AppearanceMode.appIcons.rawValue
    @AppStorage(Preferences.Key.showTabCounts.rawValue) private var showTabCounts = true
    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted

    private var previewsSelected: Bool { appearanceMode == AppearanceMode.windowPreviews.rawValue }

    var body: some View {
        Form {
            Section {
                Picker("Switcher shows", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appearanceMode) { _, newValue in
                    // ask for the permission only when the user opts into previews
                    if newValue == AppearanceMode.windowPreviews.rawValue,
                       !ScreenRecordingPermission.isGranted {
                        screenRecordingGranted = ScreenRecordingPermission.request()
                    }
                    if newValue == AppearanceMode.appIcons.rawValue {
                        // back to icons: no reason to retain any snapshot
                        PreviewProvider.shared.evictAll()
                    }
                }
                Toggle("Show tab counts", isOn: $showTabCounts)
            } footer: {
                Text("App Icons shows each window as a large application icon. Window Previews shows a snapshot of each window instead. Both show one entry per window with its title.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // this section is always present so the window height never jumps
            // when the appearance mode changes
            Section {
                if !previewsSelected {
                    Label("App Icons never needs any extra permission.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("Window Previews will ask for Screen Recording when you select it — macOS requires that permission for window snapshots.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if screenRecordingGranted {
                    Label("Screen Recording access is granted.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Snapshots are captured only while the switcher is open.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Window Previews needs Screen Recording access.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Until it's granted, the switcher automatically falls back to App Icons.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") {
                        ScreenRecordingPermission.openSystemSettings()
                    }
                    // bounded polling: only while this pane shows the pending state
                    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                        screenRecordingGranted = ScreenRecordingPermission.isGranted
                    }
                }
            } header: {
                Text("Screen Recording")
            } footer: {
                Text("Previews are generated on your Mac only while the switcher is open, kept temporarily in memory, never written to disk, and never transmitted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // fixed pane height: swapping modes must not resize the Settings window
        .frame(width: paneWidth, height: 360)
    }
}

// MARK: - Updates

struct UpdatesPane: View {
    @State private var automaticUpdates = UpdateManager.shared.automaticallyChecksForUpdates

    var body: some View {
        Form {
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
                if !UpdateManager.shared.isAvailable {
                    Text("Updates are available in the installed app (WindowHop.app), not in development builds.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Update checks against GitHub are WindowHop's only routine network activity. No telemetry, no accounts. Updates are cryptographically verified before installing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize()
    }
}

// MARK: - About

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.perso.windowhop"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("WindowHop application icon")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WindowHop")
                            .font(.title2.weight(.semibold))
                        Text("Switch between windows, not just apps.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Version", value: "\(version) (build \(build))")
                LabeledContent("Bundle identifier", value: bundleIdentifier)
            }
            Section {
                Link("WindowHop on GitHub",
                     destination: URL(string: "https://github.com/martonpaulo/windowhop")!)
                Link("Report an issue",
                     destination: URL(string: "https://github.com/martonpaulo/windowhop/issues")!)
            }
            Section {
                LabeledContent("License", value: "GPL-3.0")
                Text("Derived from AltTab by Louis Pontoise (lwouis) and contributors. Thank you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("AltTab on GitHub",
                     destination: URL(string: "https://github.com/lwouis/alt-tab-macos")!)
            } footer: {
                Text("© 2026 WindowHop contributors. Free software under the GNU GPL-3.0.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize()
    }
}
