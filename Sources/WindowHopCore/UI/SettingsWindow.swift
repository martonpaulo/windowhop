import AppKit
import SwiftUI

/// The Settings window: a native multi-pane layout (toolbar-style
/// NSTabViewController, exactly like classic System Settings panes) hosting
/// SwiftUI content. Every pane is the same size, so selecting one never resizes
/// or re-centers the window.
///
/// Its position survives relaunch through AppKit's frame autosave — OS/UI
/// restoration state under AppKit's own key, not a `Preferences` value, so
/// Restore Defaults leaves it alone. First use is centered.
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()

    /// The switcher-entry title; the window's visible title follows the pane name.
    public static let switcherEntryTitle = "WindowHop Settings"

    static let defaultFrameAutosaveName = "WindowHopSettings"

    private let frameAutosaveName: String
    private var window: NSWindow?

    init(frameAutosaveName: String = SettingsWindowController.defaultFrameAutosaveName) {
        self.frameAutosaveName = frameAutosaveName
    }

    /// The settings UI, also used by the debug render harness.
    public static func makeContentViewController() -> NSViewController {
        SettingsTabViewController()
    }

    /// Individual panes for the render harness (the toolbar lives on the window
    /// and cannot be rasterized offscreen).
    public static func makePaneViewControllers() -> [(name: String, viewController: NSViewController)] {
        SettingsPane.allCases.map { ($0.rawValue, $0.makeViewController()) }
    }

    public func show() {
        show(selecting: nil)
    }

    /// The single About surface: the app menu's About item opens this pane
    /// instead of AppKit's standard About panel.
    public func showAbout() {
        show(selecting: .about)
    }

    private func show(selecting pane: SettingsPane?) {
        let window = preparedWindow(selecting: pane)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // the Settings window is a normal switcher entry while open (the one
        // sanctioned exception to the own-window exclusion)
        WindowStore.shared.registerOwnWindow(window)
    }

    /// The retained window, created on first use at its saved position (or
    /// centered), and moved back on screen when its display is gone — checked
    /// on every show, since a display can be unplugged while it is retained.
    /// With a pane, that pane is selected (and remembered like a click on it).
    func preparedWindow(selecting pane: SettingsPane? = nil) -> NSWindow {
        let window = window ?? makeWindow()
        self.window = window
        if let pane, let tabs = window.contentViewController as? SettingsTabViewController {
            tabs.select(pane)
        }
        let recovered = WindowFrameRecovery.recoveredFrame(
            window.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            fallback: NSScreen.main?.visibleFrame)
        if recovered != window.frame {
            window.setFrame(recovered, display: false)
        }
        return window
    }

    private func makeWindow() -> NSWindow {
        let newWindow = NSWindow(contentViewController: Self.makeContentViewController())
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        // the pane canvas decides the size; only the origin comes from the
        // saved frame, so a frame saved by a build with another canvas size
        // cannot resize the window
        let canvasSize = newWindow.frame.size
        if newWindow.setFrameUsingName(frameAutosaveName) {
            let restored = newWindow.frame
            if restored.size != canvasSize {
                // keep the saved top edge, where the person placed the title bar
                newWindow.setFrame(CGRect(x: restored.minX, y: restored.maxY - canvasSize.height,
                                          width: canvasSize.width, height: canvasSize.height),
                                   display: false)
            }
        } else {
            newWindow.center()
        }
        // AppKit saves every later move under this name
        newWindow.setFrameAutosaveName(frameAutosaveName)
        return newWindow
    }
}

/// The Settings panes, in presentation order. Splitting shortcuts and window
/// filters out of General keeps every pane scannable at a glance and close to
/// the same length, instead of one pane taller than a laptop display.
enum SettingsPane: String, CaseIterable {
    case general
    case shortcuts
    case windows
    case appearance
    case updates
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .windows: "Windows"
        case .appearance: "Appearance"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .windows: "macwindow.on.rectangle"
        case .appearance: "rectangle.grid.1x2"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    @ViewBuilder private var content: some View {
        switch self {
        case .general: GeneralPane()
        case .shortcuts: ShortcutsPane()
        case .windows: WindowsPane()
        case .appearance: AppearancePane()
        case .updates: UpdatesPane()
        case .about: AboutPane()
        }
    }

    func makeViewController() -> NSHostingController<AnyView> {
        let hosting = NSHostingController(rootView: AnyView(content))
        hosting.title = title
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }
}

/// Toolbar-style panes with SF Symbols; the selected pane persists across launches.
final class SettingsTabViewController: NSTabViewController {
    /// Stores the pane's stable identifier, so adding or reordering panes never
    /// reopens Settings on a different one.
    private static let selectedPaneKey = "settingsSelectedPaneIdentifier"

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // no crossfade/slide: pane switches are instant (Reduce Motion friendly)
        transitionOptions = []
        for pane in SettingsPane.allCases {
            let item = NSTabViewItem(viewController: pane.makeViewController())
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol,
                                 accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        if let saved = UserDefaults.standard.string(forKey: Self.selectedPaneKey),
           let index = SettingsPane.allCases.firstIndex(where: { $0.rawValue == saved }) {
            selectedTabViewItemIndex = index
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var selectedPane: SettingsPane? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return (tabViewItems[selectedTabViewItemIndex].identifier as? String)
            .flatMap(SettingsPane.init(rawValue:))
    }

    func select(_ pane: SettingsPane) {
        guard let index = SettingsPane.allCases.firstIndex(of: pane) else { return }
        selectedTabViewItemIndex = index
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let identifier = tabViewItem?.identifier as? String else { return }
        UserDefaults.standard.set(identifier, forKey: Self.selectedPaneKey)
    }
}

private extension View {
    /// One canvas for every pane: identical size, content anchored at the top,
    /// scrollable when it outgrows the canvas.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(width: DesignTokens.settingsPaneWidth,
                   height: DesignTokens.settingsPaneHeight)
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var preferences = Preferences.shared
    @StateObject private var launchAtLogin = LaunchAtLoginModel()
    @State private var restoreConfirmationShown = false
    @State private var quitConfirmationShown = false

    private var switchingGuide: SwitchingGuide {
        SwitchingGuide(switcherShortcut: preferences.shortcut,
                       persistentShortcut: preferences.persistentShortcut,
                       enabled: preferences.switcherEnabled)
    }

    var body: some View {
        Form {
            // first, so the pane Settings opens on after the permission grant
            // says how to switch; derived from the current shortcuts
            Section {
                ForEach(switchingGuide.firstSteps, id: \.display) { step in
                    Text(step.display)
                        .accessibilityLabel(step.spoken)
                }
            } header: {
                Text("Switch windows")
            }
            Section {
                Toggle("Enable WindowHop", isOn: $preferences.switcherEnabled)
                // The binding, not onChange: the toggle shows the status macOS
                // reports, and only a click requests a change. A refreshed
                // status never flows back into a change handler.
                Toggle("Launch at login",
                       isOn: Binding(get: { launchAtLogin.status.isOn },
                                     set: { launchAtLogin.request($0) }))
                    .disabled(!launchAtLogin.status.allowsChange)
                if launchAtLogin.failed {
                    Label(LoginItemStatus.changeFailedExplanation,
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let explanation = launchAtLogin.status.explanation {
                    Label(explanation,
                          systemImage: launchAtLogin.status.offersLoginItemsSettings
                              ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if launchAtLogin.status.offersLoginItemsSettings {
                    Button("Open Login Items Settings…") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            } footer: {
                Text("Disabling WindowHop hands \(SwitchingGuide.nativeSwitcherChord.display) back to the native app switcher without quitting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show menu bar item", isOn: $preferences.showMenuBarItem)
                Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
            } header: {
                Text("Appears in")
            }
            Section {
                Button("Restore Defaults…") {
                    restoreConfirmationShown = true
                }
                .confirmationDialog("Restore all WindowHop settings?",
                                    isPresented: $restoreConfirmationShown) {
                    Button("Restore Defaults") {
                        SettingsDefaultsRestorer.shared.restore()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Shortcuts, appearance, window filters, update checks, and app visibility return to their original values. macOS permissions, launch at login and cached previews are unchanged.")
                }
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
                    Text("The native \(SwitchingGuide.nativeSwitcherChord.display) app switcher takes over until you open WindowHop again.")
                }
            }
        }
        .settingsPane()
        // the window is retained, so re-read what System Settings may have
        // changed whenever the pane shows or WindowHop becomes active; nothing polls
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var preferences = Preferences.shared
    @State private var shortcutValidationMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Switcher shortcut", selection: $preferences.shortcut) {
                    ForEach(ShortcutSpec.allCases) { spec in
                        Text(spec.displayName).tag(spec)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: preferences.shortcut) { _, newValue in
                    // a switcher-shortcut change can invalidate the persistent chord
                    if let current = preferences.persistentShortcut,
                       let error = current.validate(against: newValue) {
                        preferences.persistentShortcut = nil
                        shortcutValidationMessage = error.explanation
                    }
                }
                LabeledContent("Open WindowHop") {
                    ShortcutRecorderField(shortcut: $preferences.persistentShortcut,
                                          validationMessage: $shortcutValidationMessage,
                                          switcherShortcut: preferences.shortcut,
                                          onRecordingChanged: { recording in
                                              SwitcherController.shared
                                                  .setShortcutRecordingActive(recording)
                                          })
                }
                if let shortcutValidationMessage {
                    Text(shortcutValidationMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                let reference = SwitchingGuide(switcherShortcut: preferences.shortcut,
                                               persistentShortcut: preferences.persistentShortcut,
                                               enabled: preferences.switcherEnabled).keyReference
                Text(reference.map(\.display).joined(separator: " "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(reference.map(\.spoken).joined(separator: " "))
            }
        }
        .settingsPane()
        // the message explains the change that just happened here; leaving the
        // pane (to restore defaults, for instance) makes it obsolete
        .onDisappear { shortcutValidationMessage = nil }
    }
}

// MARK: - Windows

struct WindowsPane: View {
    @ObservedObject private var preferences = Preferences.shared
    @StateObject private var connectedDisplays = ConnectedDisplaysModel()

    /// One entry per selectable display. A chosen display that is currently
    /// disconnected stays in the list, named as such: dropping it would destroy
    /// the user's choice every time a monitor is unplugged.
    private struct DisplayOption: Identifiable, Hashable {
        let id: String
        let label: String
    }

    private var displayOptions: [DisplayOption] {
        var options = connectedDisplays.displays.map {
            DisplayOption(id: $0.id, label: $0.name)
        }
        if let chosen = preferences.switcherDisplayID,
           !connectedDisplays.displays.contains(where: { $0.id == chosen }) {
            options.append(DisplayOption(id: chosen, label: "Selected display (disconnected)"))
        }
        return options
    }

    /// UserDefaults cannot hold nil, and a Picker cannot select it either; the
    /// empty string is the single representation of "no display chosen".
    private var chosenDisplay: Binding<String> {
        Binding(get: { preferences.switcherDisplayID ?? "" },
                set: { preferences.switcherDisplayID = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Include windows from other Spaces", isOn: $preferences.includeOtherSpaces)
                Toggle("Include windows from other displays", isOn: $preferences.includeOtherDisplays)
                Toggle("Include minimized windows", isOn: $preferences.includeMinimizedWindows)
                Toggle("Include windows from hidden applications",
                       isOn: $preferences.includeHiddenApplicationWindows)
                Toggle("Include Picture-in-Picture windows",
                       isOn: $preferences.includePictureInPictureWindows)
            } header: {
                Text("Windows shown")
            } footer: {
                Text("WindowHop shows a curated set of normal windows by default. Additional categories are opt-in and update the switcher immediately. Menus, tooltips, tab siblings, and system overlays are never listed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Show the switcher on",
                       selection: $preferences.switcherDisplayPlacement) {
                    ForEach(SwitcherDisplayPlacement.allCases) { placement in
                        Text(placement.displayName).tag(placement)
                    }
                }
                if preferences.switcherDisplayPlacement == .specificDisplay {
                    Picker("Display", selection: chosenDisplay) {
                        ForEach(displayOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                }
            } header: {
                Text("Switcher placement")
            } footer: {
                Text("This is where the switcher appears, not which windows it lists. The display with the pointer is the one you are looking at, which is not always the one holding keyboard focus. If a specific display is disconnected, the switcher opens on the display with the pointer and returns to your choice when that display is reconnected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Delay before showing the switcher",
                       selection: $preferences.switcherRevealDelay) {
                    ForEach(SwitcherRevealDelay.allCases) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Switcher delay")
            } footer: {
                Text("While you hold the switcher shortcut, the switcher appears after this delay. A quicker press switches to your previous window without showing it. Open WindowHop always shows the switcher immediately. The default is \(Preferences.Defaults.switcherRevealDelay.displayName).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .onAppear { connectedDisplays.startObserving() }
        .onDisappear { connectedDisplays.stopObserving() }
        .onChange(of: preferences.switcherDisplayPlacement) { _, placement in
            // choosing "a specific display" with nothing stored would show an
            // empty picker; preselect the display the pointer is on
            guard placement == .specificDisplay, preferences.switcherDisplayID == nil else { return }
            preferences.switcherDisplayID = DisplayRegistry.pointerDisplayID()
                ?? connectedDisplays.displays.first?.id
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @ObservedObject private var preferences = Preferences.shared
    @State private var screenRecordingStatus = ScreenRecordingPermission.status

    private var previewsSelected: Bool { preferences.appearanceMode == .windowPreviews }

    var body: some View {
        Form {
            Section {
                Picker("Switcher shows", selection: $preferences.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: preferences.appearanceMode) { _, newValue in
                    // ask for the permission only when the user opts into previews
                    if newValue == .windowPreviews, !ScreenRecordingPermission.isGranted {
                        _ = ScreenRecordingPermission.request()
                        screenRecordingStatus = ScreenRecordingPermission.status
                    }
                    if newValue == .appIcons {
                        // back to icons: no reason to retain any snapshot
                        PreviewProvider.shared.evictAll()
                    }
                }
                Toggle("Show tab counts", isOn: $preferences.showTabCounts)
            } footer: {
                Text("App Icons shows each window as a large application icon. Window Previews shows a snapshot of each window instead. Both show one entry per window with its title.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Show an expanded preview after pausing",
                       selection: $preferences.expandedPreviewDelay) {
                    ForEach(ExpandedPreviewDelay.allCases) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                }
                .pickerStyle(.menu)
                // App Icons has no snapshot to enlarge; the stored delay is
                // kept, so switching back to Window Previews restores it
                .disabled(!preferences.appearanceMode.supportsExpandedPreview)
            } header: {
                Text("Expanded Preview")
            } footer: {
                // one text for both modes, so the pane height never changes
                Text("Window Previews only. After you pause, WindowHop enlarges the latest snapshot inside the switcher. The real window is not activated until you confirm; cancelling leaves the desktop unchanged. The default delay is 3 seconds.")
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
                } else if screenRecordingStatus.isAuthorized {
                    Label("Screen Recording access is granted.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Snapshots are captured only while the switcher is open.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Window Previews needs Screen Recording access.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Until it is granted, cached previews remain visible and other cards use a static fallback instead of an indefinite loading animation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(screenRecordingStatus == .notDetermined
                           ? "Grant Permission"
                           : "Open System Settings") {
                        if screenRecordingStatus == .notDetermined {
                            _ = ScreenRecordingPermission.request()
                            screenRecordingStatus = ScreenRecordingPermission.status
                        } else {
                            ScreenRecordingPermission.openSystemSettings()
                        }
                    }
                }
            } header: {
                Text("Screen Recording")
            } footer: {
                Text("Captures run only while the switcher is open. Recent tile-sized previews may remain in memory for the next open; they are never written to disk or transmitted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            screenRecordingStatus = ScreenRecordingPermission.status
        }
    }
}

// MARK: - Updates

struct UpdatesPane: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    private let appVersion = AppVersion.main

    var body: some View {
        Form {
            if let availableVersion = updateManager.availableVersion {
                Section {
                    // mirrors Sparkle's own prompt: installing (or postponing/
                    // skipping) continues in the standard Sparkle dialog
                    LabeledContent {
                        Button("Install Update…") {
                            UpdateManager.shared.checkForUpdates()
                        }
                    } label: {
                        Label("WindowHop \(availableVersion) is available",
                              systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }
            Section {
                Toggle("Automatically check for updates",
                       isOn: $preferences.automaticUpdateChecks)
                    .onChange(of: preferences.automaticUpdateChecks) { _, newValue in
                        UpdateManager.shared.automaticallyChecksForUpdates = newValue
                    }
                    .disabled(!UpdateManager.shared.isAvailable)
                LabeledContent {
                    Button("Check for Updates…") {
                        UpdateManager.shared.checkForUpdates()
                    }
                    .disabled(!UpdateManager.shared.isAvailable)
                } label: {
                    Text(appVersion.versionLabel)
                    if let released = appVersion.releaseDateText() {
                        Text("Released \(released)")
                    }
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
        .settingsPane()
    }
}

// MARK: - About

struct AboutPane: View {
    private let appVersion = AppVersion.main

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.perso.windowhop"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: DesignTokens.settingsAboutHeaderSpacing) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: DesignTokens.settingsAboutIconSize,
                               height: DesignTokens.settingsAboutIconSize)
                        .accessibilityLabel("WindowHop application icon")
                    VStack(alignment: .leading, spacing: DesignTokens.settingsAboutTitleSpacing) {
                        Text("WindowHop")
                            .font(.title2.weight(.semibold))
                        Text("Switch between windows, not just apps.")
                            .foregroundStyle(.secondary)
                        Text("Developed by Marton Paulo")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, DesignTokens.settingsAboutTitleSpacing)
                    }
                }
                .padding(.vertical, DesignTokens.settingsAboutHeaderPadding)
                LabeledContent("Version", value: appVersion.displayVersion)
                if let released = appVersion.releaseDateText() {
                    LabeledContent("Released", value: released)
                }
                LabeledContent("Bundle identifier", value: bundleIdentifier)
            }
            Section {
                Link("WindowHop Website", destination: ProjectLinks.website)
                Link("WindowHop on GitHub",
                     destination: ProjectLinks.repository)
                Link("Report an issue",
                     destination: ProjectLinks.issues)
            }
            Section {
                LabeledContent("License", value: "GPL-3.0")
                Text("Derived from AltTab by Louis Pontoise (lwouis) and contributors. Thank you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("AltTab on GitHub",
                     destination: ProjectLinks.altTabRepository)
            } footer: {
                // the bundle's canonical line; omitted rather than invented
                // when no Info.plist is embedded (swift build runs)
                if let copyright = appVersion.copyright {
                    Text(copyright)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsPane()
    }
}
