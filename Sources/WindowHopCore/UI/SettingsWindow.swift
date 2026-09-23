import AppKit
import SwiftUI
import WindowHopKit

/// The Settings window: a native multi-pane layout (toolbar-style
/// NSTabViewController, like the settings of Safari or Mail) hosting SwiftUI
/// content. Each pane is as tall as its content, so the window resizes when the
/// pane changes, keeping its top edge in place (#121).
///
/// Its position survives relaunch through AppKit's frame autosave — OS/UI
/// restoration state under AppKit's own key, not a `Preferences` value, so
/// Restore Defaults leaves it alone. First use is centered.
@MainActor
public final class SettingsWindowController {
    /// What the panes read and act on.
    private let dependencies: SettingsDependencies
    /// Makes the window a switcher entry while it is open.
    private let registerOwnWindow: (NSWindow) -> Void

    /// The switcher-entry title; the window's visible title follows the pane name.
    public static let switcherEntryTitle = String(localized: "WindowHop Settings")

    public static let defaultFrameAutosaveName = "WindowHopSettings"

    private let frameAutosaveName: String
    private var window: NSWindow?

    /// Owned by `AppDelegate`; tests pass their own autosave name.
    public init(
        dependencies: SettingsDependencies,
        registerOwnWindow: @escaping (NSWindow) -> Void,
        frameAutosaveName: String = SettingsWindowController.defaultFrameAutosaveName
    ) {
        self.dependencies = dependencies
        self.registerOwnWindow = registerOwnWindow
        self.frameAutosaveName = frameAutosaveName
    }

    /// The settings UI, also used by the debug render harness, which can open
    /// it on a pane by its identifier (a 2.0.0 identifier included).
    public static func makeContentViewController(
        _ dependencies: SettingsDependencies,
        selecting paneIdentifier: String? = nil
    ) -> NSViewController {
        let tabs = SettingsTabViewController(dependencies)
        if let pane = paneIdentifier.flatMap(SettingsPane.init(savedIdentifier:)) {
            tabs.select(pane)
        }
        return tabs
    }

    /// Individual panes for the render harness (the toolbar lives on the window
    /// and cannot be rasterized offscreen).
    public static func makePaneViewControllers(
        _ dependencies: SettingsDependencies
    ) -> [(name: String, viewController: NSViewController)] {
        SettingsPane.allCases.map { ($0.rawValue, $0.makeViewController(dependencies)) }
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
        registerOwnWindow(window)
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
        let newWindow = NSWindow(contentViewController: Self.makeContentViewController(dependencies))
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        // the selected pane decides the size; only the top edge comes from the
        // saved frame, so a frame saved with another pane, or by a build with
        // another layout, cannot resize the window
        let canvasSize = newWindow.frame.size
        if newWindow.setFrameUsingName(frameAutosaveName) {
            let restored = newWindow.frame
            if restored.size != canvasSize {
                // keep the saved top edge, where the person placed the title bar
                newWindow.setFrame(
                    CGRect(
                        x: restored.minX, y: restored.maxY - canvasSize.height,
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

/// What the Settings panes read and act on. `AppDelegate` builds it from the
/// objects it owns; the debug harness and tests build their own. Each pane
/// receives only the members it uses, through its initializer.
@MainActor
public struct SettingsDependencies {
    public let preferences: Preferences
    public let restorer: SettingsDefaultsRestorer
    public let updateManager: UpdateManager
    /// Tells the event tap that the shortcut recorder is recording.
    public let setShortcutRecordingActive: (Bool) -> Void
    /// Drops every cached preview (a switch back to App Icons).
    public let evictPreviews: () -> Void

    public init(
        preferences: Preferences,
        restorer: SettingsDefaultsRestorer,
        updateManager: UpdateManager,
        setShortcutRecordingActive: @escaping (Bool) -> Void,
        evictPreviews: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.restorer = restorer
        self.updateManager = updateManager
        self.setShortcutRecordingActive = setShortcutRecordingActive
        self.evictPreviews = evictPreviews
    }
}

/// The Settings panes, in presentation order. General holds the app itself,
/// Shortcuts the keys, Switcher everything about what the switcher shows and
/// where, and About the version, updates, and credits (#121).
enum SettingsPane: String, CaseIterable {
    case general
    case shortcuts
    case switcher
    case about

    /// The pane a saved identifier names. 2.0.0 had six panes; a person who
    /// last used one of the merged ones reopens on the pane that now holds it.
    init?(savedIdentifier: String) {
        switch savedIdentifier {
        case "windows", "appearance": self = .switcher
        case "updates": self = .about
        default: self.init(rawValue: savedIdentifier)
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .shortcuts: String(localized: "Shortcuts")
        case .switcher: String(localized: "Switcher")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .switcher: "macwindow.on.rectangle"
        case .about: "info.circle"
        }
    }

    @MainActor @ViewBuilder private func content(_ dependencies: SettingsDependencies) -> some View {
        let preferences = dependencies.preferences
        switch self {
        case .general:
            GeneralPane(preferences: preferences, restorer: dependencies.restorer)
        case .shortcuts:
            ShortcutsPane(
                preferences: preferences,
                setShortcutRecordingActive: dependencies.setShortcutRecordingActive)
        case .switcher:
            SwitcherPane(preferences: preferences, evictPreviews: dependencies.evictPreviews)
        case .about:
            AboutPane(preferences: preferences, updateManager: dependencies.updateManager)
        }
    }

    @MainActor
    func makeViewController(_ dependencies: SettingsDependencies) -> NSHostingController<AnyView> {
        let hosting = NSHostingController(rootView: AnyView(content(dependencies)))
        hosting.title = title
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }
}

/// Toolbar-style panes with SF Symbols; the selected pane persists across launches.
final class SettingsTabViewController: NSTabViewController {
    /// Stores the pane's stable identifier, so adding or reordering panes never
    /// reopens Settings on a different one.
    static let selectedPaneKey = "settingsSelectedPaneIdentifier"

    init(_ dependencies: SettingsDependencies) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // no crossfade/slide: pane switches are instant (Reduce Motion friendly)
        transitionOptions = []
        for pane in SettingsPane.allCases {
            let item = NSTabViewItem(viewController: pane.makeViewController(dependencies))
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(
                systemSymbolName: pane.symbol,
                accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        if let saved = UserDefaults.standard.string(forKey: Self.selectedPaneKey),
            let pane = SettingsPane(savedIdentifier: saved)
        {
            select(pane)
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

extension View {
    /// Every pane is one fixed width and as tall as its content, which the
    /// hosting controller turns into the window size. A pane taller than the
    /// display stops at the display's usable height and scrolls.
    fileprivate func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(width: DesignTokens.settingsPaneWidth)
            .frame(maxHeight: settingsPaneMaxHeight())
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Secondary, callout-sized explanatory text: footers and inline notes.
    fileprivate func settingsNote() -> some View {
        font(.callout).foregroundStyle(.secondary)
    }
}

/// The tallest pane that still leaves the window's title bar and toolbar on
/// the main display.
@MainActor
private func settingsPaneMaxHeight() -> CGFloat {
    let usable = NSScreen.main?.visibleFrame.height ?? DesignTokens.settingsPaneFallbackDisplayHeight
    return max(usable - DesignTokens.settingsWindowChromeAllowance, DesignTokens.settingsPaneMinimumHeight)
}

/// A permission's state as a row value: a green check when granted, an orange
/// warning otherwise. The words carry the state, so color is never the only cue.
private struct PermissionStatus: View {
    let granted: Bool

    var body: some View {
        if granted {
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Not allowed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

/// One key drawn as a key cap, like the keys in the macOS keyboard settings.
/// The application icon at `size` points. AppKit draws it, so it picks the icon
/// file's representation for that size and the display's scale; SwiftUI's
/// `resizable()` scaled the 1024 px image down and left jagged edges (#122).
private struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon(size: size))
            .frame(width: size, height: size)
    }

    private static func icon(size: CGFloat) -> NSImage {
        let source = NSApp.applicationIconImage ?? NSImage()
        // the handler runs at each drawing's backing scale, so the choice of
        // representation follows the display the window is on
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}

private struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.callout)
            .frame(minWidth: DesignTokens.settingsKeyCapMinWidth)
            .padding(.horizontal, DesignTokens.settingsKeyCapHorizontalPadding)
            .padding(.vertical, DesignTokens.settingsKeyCapVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.settingsKeyCapCornerRadius)
                    .strokeBorder(.tertiary, lineWidth: DesignTokens.settingsKeyCapStrokeWidth))
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable private var preferences: Preferences
    private let restorer: SettingsDefaultsRestorer
    @State private var launchAtLogin: LaunchAtLoginModel
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var restoreConfirmationShown = false
    @State private var quitConfirmationShown = false

    init(preferences: Preferences, restorer: SettingsDefaultsRestorer) {
        self.preferences = preferences
        self.restorer = restorer
        _launchAtLogin = State(initialValue: LaunchAtLoginModel(preferences: preferences))
    }

    private var status: SwitchingGuide.Phrase {
        SwitchingGuide(
            switcherShortcut: preferences.shortcut,
            persistentShortcut: preferences.persistentShortcut,
            enabled: preferences.switcherEnabled
        ).status
    }

    var body: some View {
        Form {
            Section {
                // first, so the pane Settings opens on after the permission
                // grant says whether and how WindowHop switches
                HStack(spacing: DesignTokens.settingsStatusSpacing) {
                    AppIconImage(size: DesignTokens.settingsStatusIconSize)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignTokens.settingsAboutTitleSpacing) {
                        Text("WindowHop").font(.headline)
                        Text(status.display)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(status.spoken)
                    }
                    Spacer()
                    Toggle("Enable WindowHop", isOn: $preferences.switcherEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                // The binding, not onChange: the toggle shows the status macOS
                // reports, and only a click requests a change. A refreshed
                // status never flows back into a change handler.
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { launchAtLogin.status.isOn },
                        set: { launchAtLogin.request($0) })
                )
                .disabled(!launchAtLogin.status.allowsChange)
                if launchAtLogin.failed {
                    Label(
                        LoginItemStatus.changeFailedExplanation,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .settingsNote()
                } else if let explanation = launchAtLogin.status.explanation {
                    Label(
                        explanation,
                        systemImage: launchAtLogin.status.offersLoginItemsSettings
                            ? "exclamationmark.triangle.fill" : "info.circle"
                    )
                    .settingsNote()
                }
                if launchAtLogin.status.offersLoginItemsSettings {
                    Button("Open Login Items Settings…") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            }
            Section {
                Toggle("Menu bar", isOn: $preferences.showMenuBarItem)
                Toggle("Dock", isOn: $preferences.showDockIcon)
            } header: {
                Text("Show WindowHop in")
            } footer: {
                Text("When both are off, open WindowHop again to show this window.")
                    .settingsNote()
            }
            Section {
                LabeledContent {
                    PermissionStatus(granted: accessibilityGranted)
                } label: {
                    Text("Accessibility")
                    Text("Needed to list and switch windows.")
                }
                if !accessibilityGranted {
                    Button("Open System Settings…") {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            } header: {
                Text("Permissions")
            }
            Section {
                HStack {
                    Button("Restore Defaults…") {
                        restoreConfirmationShown = true
                    }
                    .confirmationDialog(
                        "Restore all WindowHop settings?",
                        isPresented: $restoreConfirmationShown
                    ) {
                        Button("Restore Defaults") {
                            restorer.restore()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Shortcuts, appearance, window filters, update checks, and app visibility return to their original values. macOS permissions, launch at login and cached previews are unchanged."
                        )
                    }
                    Spacer()
                    // quitting loses no data, so the button is not styled as
                    // destructive; the confirmation still says what changes
                    Button("Quit WindowHop…") {
                        quitConfirmationShown = true
                    }
                    .confirmationDialog(
                        "Quit WindowHop?",
                        isPresented: $quitConfirmationShown
                    ) {
                        Button("Quit WindowHop") {
                            NSApp.terminate(nil)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "The native \(SwitchingGuide.nativeSwitcherChord.display) app switcher takes over until you open WindowHop again."
                        )
                    }
                }
            }
        }
        .settingsPane()
        // the window is retained, so re-read what System Settings may have
        // changed whenever the pane shows or WindowHop becomes active; nothing polls
        .onAppear { refreshSystemState() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshSystemState()
        }
    }

    private func refreshSystemState() {
        launchAtLogin.refresh()
        accessibilityGranted = AccessibilityPermission.isGranted
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @Bindable var preferences: Preferences
    let setShortcutRecordingActive: (Bool) -> Void
    @State private var shortcutValidationMessage: String?

    private var guide: SwitchingGuide {
        SwitchingGuide(
            switcherShortcut: preferences.shortcut,
            persistentShortcut: preferences.persistentShortcut,
            enabled: preferences.switcherEnabled)
    }

    var body: some View {
        let guide = guide
        Form {
            Section {
                Picker(selection: $preferences.shortcut) {
                    ForEach(ShortcutSpec.allCases) { spec in
                        Text(spec.displayName).tag(spec)
                    }
                } label: {
                    Text("Switch windows")
                    Text(guide.heldHint.display)
                        .accessibilityLabel(guide.heldHint.spoken)
                }
                .pickerStyle(.menu)
                .onChange(of: preferences.shortcut) { _, newValue in
                    // a switcher-shortcut change can invalidate the persistent chord
                    if let current = preferences.persistentShortcut,
                        let error = current.validate(against: newValue)
                    {
                        preferences.persistentShortcut = nil
                        shortcutValidationMessage = error.explanation
                    }
                }
                LabeledContent {
                    ShortcutRecorderField(
                        shortcut: $preferences.persistentShortcut,
                        validationMessage: $shortcutValidationMessage,
                        switcherShortcut: preferences.shortcut,
                        onRecordingChanged: setShortcutRecordingActive
                    )
                    .frame(width: DesignTokens.settingsRecorderWidth)
                } label: {
                    Text("Open WindowHop")
                    Text(guide.persistentHint.display)
                        .accessibilityLabel(guide.persistentHint.spoken)
                }
                if let shortcutValidationMessage {
                    Text(shortcutValidationMessage)
                        .settingsNote()
                }
                // the delay belongs to the held shortcut, so it sits under it
                Picker(selection: $preferences.switcherRevealDelay) {
                    ForEach(SwitcherRevealDelay.allCases) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                } label: {
                    Text("Delay before showing")
                    Text("A quicker press switches without showing the switcher.")
                }
                .pickerStyle(.menu)
            }
            Section {
                ForEach(guide.sessionKeys) { row in
                    LabeledContent(row.action) {
                        HStack(spacing: DesignTokens.settingsKeyCapSpacing) {
                            ForEach(row.keys, id: \.display) { key in
                                KeyCap(key: key.display)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
                }
            } header: {
                Text("While the switcher is open")
            }
        }
        .settingsPane()
        // the message explains the change that just happened here; leaving the
        // pane (to restore defaults, for instance) makes it obsolete
        .onDisappear { shortcutValidationMessage = nil }
    }
}

// MARK: - Switcher

struct SwitcherPane: View {
    @Bindable var preferences: Preferences
    let evictPreviews: () -> Void
    @State private var screenRecordingStatus = ScreenRecordingPermission.status
    @State private var connectedDisplays = ConnectedDisplaysModel()

    private var previewsSelected: Bool { preferences.appearanceMode == .windowPreviews }

    /// UserDefaults holds a placement and a display identifier; the menu shows
    /// them as one choice (`SwitcherPlacementChoice`).
    private var placementChoice: Binding<SwitcherPlacementChoice> {
        Binding(
            get: {
                SwitcherPlacementChoice(
                    placement: preferences.switcherDisplayPlacement,
                    displayID: preferences.switcherDisplayID)
            },
            set: { choice in
                preferences.switcherDisplayID = choice.displayID(keeping: preferences.switcherDisplayID)
                preferences.switcherDisplayPlacement = choice.placement
            })
    }

    private var displayEntries: [SwitcherPlacementChoice.DisplayEntry] {
        SwitcherPlacementChoice.displayEntries(
            connected: connectedDisplays.displays.map {
                SwitcherPlacementChoice.DisplayEntry(id: $0.id, name: $0.name)
            },
            chosenDisplayID: preferences.switcherDisplayPlacement == .specificDisplay
                ? preferences.switcherDisplayID : nil,
            disconnectedLabel: String(localized: "Selected display (disconnected)"))
    }

    var body: some View {
        Form {
            Section {
                AppearanceModePicker(selection: $preferences.appearanceMode)
                    .onChange(of: preferences.appearanceMode) { _, newValue in
                        // ask for the permission only when the user opts into previews
                        if newValue == .windowPreviews, !ScreenRecordingPermission.isGranted {
                            _ = ScreenRecordingPermission.request()
                            screenRecordingStatus = ScreenRecordingPermission.status
                        }
                        if newValue == .appIcons {
                            // back to icons: no reason to retain any snapshot
                            evictPreviews()
                        }
                    }
                Toggle(isOn: $preferences.showTabCounts) {
                    Text("Show tab counts")
                    Text("A badge with the number of tabs in a window.")
                }
                // App Icons has no snapshot to enlarge and needs no extra
                // permission; the stored delay is kept for a switch back
                if previewsSelected {
                    Picker(selection: $preferences.expandedPreviewDelay) {
                        ForEach(ExpandedPreviewDelay.allCases) { delay in
                            Text(delay.displayName).tag(delay)
                        }
                    } label: {
                        Text("Enlarge preview after a pause")
                        Text("The window is not activated until you confirm.")
                    }
                    .pickerStyle(.menu)
                    LabeledContent {
                        PermissionStatus(granted: screenRecordingStatus.isAuthorized)
                    } label: {
                        Text("Screen Recording")
                        Text("Captured only while the switcher is open. Never saved to disk or sent.")
                    }
                    if !screenRecordingStatus.isAuthorized {
                        Button(
                            screenRecordingStatus == .notDetermined
                                ? "Grant Permission…"
                                : "Open System Settings…"
                        ) {
                            if screenRecordingStatus == .notDetermined {
                                _ = ScreenRecordingPermission.request()
                                screenRecordingStatus = ScreenRecordingPermission.status
                            } else {
                                ScreenRecordingPermission.openSystemSettings()
                            }
                        }
                    }
                }
            } header: {
                Text("Style")
            }
            Section {
                Toggle("Other Spaces", isOn: $preferences.includeOtherSpaces)
                Toggle("Other displays", isOn: $preferences.includeOtherDisplays)
                Toggle("Minimized windows", isOn: $preferences.includeMinimizedWindows)
                Toggle("Hidden apps", isOn: $preferences.includeHiddenApplicationWindows)
                Toggle("Picture in Picture", isOn: $preferences.includePictureInPictureWindows)
            } header: {
                Text("Include windows from")
            } footer: {
                Text("Tabs of one window are one entry. Menus and system overlays are never listed.")
                    .settingsNote()
            }
            Section {
                Picker("Show the switcher on", selection: placementChoice) {
                    Text(SwitcherDisplayPlacement.allDisplays.displayName)
                        .tag(SwitcherPlacementChoice.allDisplays)
                    Text(SwitcherDisplayPlacement.pointerDisplay.displayName)
                        .tag(SwitcherPlacementChoice.pointerDisplay)
                    if !displayEntries.isEmpty {
                        Divider()
                        ForEach(displayEntries) { entry in
                            Text(entry.name).tag(SwitcherPlacementChoice.display(id: entry.id))
                        }
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Placement")
            } footer: {
                Text("While a chosen display is disconnected, the switcher opens on the display with the pointer.")
                    .settingsNote()
            }
        }
        .settingsPane()
        .onAppear { connectedDisplays.startObserving() }
        .onDisappear { connectedDisplays.stopObserving() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            screenRecordingStatus = ScreenRecordingPermission.status
        }
    }
}

/// App Icons or Window Previews, chosen by a thumbnail of each, like the
/// appearance picker in System Settings. It is one control for VoiceOver, with
/// each option a selectable button.
private struct AppearanceModePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: DesignTokens.settingsStyleOptionSpacing) {
            ForEach(AppearanceMode.allCases) { mode in
                let selected = selection == mode
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: DesignTokens.settingsStyleLabelSpacing) {
                        StyleThumbnail(mode: mode)
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: DesignTokens.settingsStyleThumbnailCornerRadius
                                        + DesignTokens.settingsStyleSelectionInset
                                )
                                .inset(by: -DesignTokens.settingsStyleSelectionInset)
                                .strokeBorder(
                                    selected ? Color.accentColor : .clear,
                                    lineWidth: DesignTokens.settingsStyleSelectionWidth))
                        Text(mode.displayName)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.settingsStylePickerPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switcher style")
    }
}

/// A miniature switcher: three app icons, or three window snapshots.
private struct StyleThumbnail: View {
    let mode: AppearanceMode

    var body: some View {
        HStack(spacing: DesignTokens.settingsStyleThumbnailItemSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                switch mode {
                case .appIcons:
                    RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailIconCornerRadius)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(
                            width: DesignTokens.settingsStyleThumbnailIconSize,
                            height: DesignTokens.settingsStyleThumbnailIconSize)
                case .windowPreviews:
                    RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailPreviewCornerRadius)
                        .fill(.tertiary)
                        .frame(
                            width: DesignTokens.settingsStyleThumbnailPreviewWidth,
                            height: DesignTokens.settingsStyleThumbnailPreviewHeight)
                }
            }
        }
        .frame(
            width: DesignTokens.settingsStyleThumbnailWidth,
            height: DesignTokens.settingsStyleThumbnailHeight
        )
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailCornerRadius)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailCornerRadius)
                .strokeBorder(.separator)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - About

struct AboutPane: View {
    @Bindable var preferences: Preferences
    let updateManager: UpdateManager
    private let appVersion = AppVersion.main

    /// "Version 2.1.0 (20100) · 23 September 2026", or the version alone.
    private var versionLine: String {
        guard let released = appVersion.releaseDateText() else { return appVersion.versionLabel }
        return String(
            localized: "\(appVersion.versionLabel) · \(released)",
            comment: "The version label, then the release date.")
    }

    private var updateStatus: String {
        if !updateManager.isAvailable {
            return String(localized: "Updates work in the installed app, not in development builds.")
        }
        if let lastCheck = updateManager.lastCheckDate {
            return String(
                localized: "Last checked \(lastCheck.formatted(.relative(presentation: .named))).",
                comment: "The placeholder is a relative time, such as 2 hours ago.")
        }
        return String(localized: "Not checked yet.")
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: DesignTokens.settingsAboutTitleSpacing) {
                    AppIconImage(size: DesignTokens.settingsAboutIconSize)
                        .accessibilityLabel("WindowHop application icon")
                    Text("WindowHop")
                        .font(.title2.weight(.semibold))
                    Text("Switch between windows, not just apps.")
                        .foregroundStyle(.secondary)
                    Text("Made by Marton Paulo")
                        .settingsNote()
                    Text(versionLine)
                        .settingsNote()
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.settingsAboutHeaderPadding)
            }
            Section {
                if let availableVersion = updateManager.availableVersion {
                    // mirrors Sparkle's own prompt: installing (or postponing/
                    // skipping) continues in the standard Sparkle dialog
                    LabeledContent {
                        Button("Install Update…") {
                            updateManager.checkForUpdates()
                        }
                    } label: {
                        Label(
                            "WindowHop \(availableVersion) is available",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .foregroundStyle(.tint)
                    }
                }
                Toggle(
                    "Check for updates automatically",
                    isOn: $preferences.automaticUpdateChecks
                )
                .onChange(of: preferences.automaticUpdateChecks) { _, newValue in
                    updateManager.automaticallyChecksForUpdates = newValue
                }
                .disabled(!updateManager.isAvailable)
                LabeledContent {
                    Button("Check for Updates…") {
                        updateManager.checkForUpdates()
                    }
                    .disabled(!updateManager.isAvailable)
                } label: {
                    Text(updateStatus)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Update checks are WindowHop's only network activity. No telemetry.")
                    .settingsNote()
            }
            Section {
                VStack(spacing: DesignTokens.settingsAboutFooterSpacing) {
                    HStack(spacing: DesignTokens.settingsAboutLinkSpacing) {
                        Link("Website", destination: ProjectLinks.website)
                        Link("GitHub", destination: ProjectLinks.repository)
                        // opens the prefilled form in the browser; nothing is sent
                        // until the person reviews and submits it there
                        Link(
                            "Report an Issue…",
                            destination: ProjectLinks.issueReport(
                                for: appVersion, macOS: ProcessInfo.processInfo.operatingSystemVersion))
                    }
                    // the bundle's canonical line, with the AltTab credit as text
                    // (#123); omitted rather than invented when no Info.plist is
                    // embedded (swift build runs)
                    if let copyright = appVersion.copyright {
                        Text(copyright)
                            .settingsNote()
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .settingsPane()
    }
}
