import Foundation
import Combine

/// The two switcher presentations. App Icons is the default and never needs
/// Screen Recording permission; Window Previews shows live window snapshots.
/// There are deliberately no further themes, styles, or size options.
public enum AppearanceMode: String, CaseIterable, Identifiable {
    case appIcons
    case windowPreviews

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appIcons: return "App Icons"
        case .windowPreviews: return "Window Previews"
        }
    }
}

/// User-facing dwell presets for expanding the targeted window inside
/// WindowHop. The external window is never activated by this preview.
public enum ExpandedPreviewDelay: String, CaseIterable, Identifiable {
    case off
    case oneSecond
    case twoSeconds
    case threeSeconds
    case fiveSeconds

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .oneSecond: return "1 second"
        case .twoSeconds: return "2 seconds"
        case .threeSeconds: return "3 seconds"
        case .fiveSeconds: return "5 seconds"
        }
    }

    public var duration: TimeInterval? {
        switch self {
        case .off: return nil
        case .oneSecond: return 1
        case .twoSeconds: return 2
        case .threeSeconds: return 3
        case .fiveSeconds: return 5
        }
    }
}

/// All WindowHop settings with their defaults. This observable model is the
/// single runtime source of truth; UserDefaults is only its persistence layer.
/// The store is injectable for deterministic migration and persistence tests.
public final class Preferences: ObservableObject {
    public static let shared = Preferences()
    public static let windowFiltersDidChange = Notification.Name(
        "com.perso.windowhop.windowFiltersDidChange")

    public enum Key: String, CaseIterable {
        case switcherEnabled
        case launchAtLogin
        case shortcut
        case persistentShortcut
        case appearanceMode
        /// Kept only to migrate 1.1.2 dwell presets.
        case navigationPreviewDelay
        case expandedPreviewDelay
        case switcherDisplayPlacement
        /// The persistent UUID of the display chosen for `.specificDisplay`.
        case switcherDisplayID
        case includeOtherSpaces
        case includeOtherDisplays
        case includeMinimizedWindows
        case includeHiddenApplicationWindows
        case includePictureInPictureWindows
        case showTabCounts
        case showMenuBarItem
        case showDockIcon
        case automaticUpdateChecks = "SUEnableAutomaticChecks"
        case firstLaunchCompleted
    }

    /// The only source for product defaults. Views, registration, migration,
    /// Restore Defaults, and tests consume these values instead of restating them.
    public enum Defaults {
        public static let switcherEnabled = true
        public static let launchAtLogin = true
        public static let shortcut = ShortcutSpec.commandTab
        public static let persistentShortcut: PersistentShortcut? = .optionTab
        public static let appearanceMode = AppearanceMode.appIcons
        public static let expandedPreviewDelay = ExpandedPreviewDelay.threeSeconds
        public static let switcherDisplayPlacement = SwitcherDisplayPlacement.allDisplays
        public static let switcherDisplayID: String? = nil
        public static let includeOtherSpaces = true
        public static let includeOtherDisplays = true
        public static let includeMinimizedWindows = false
        public static let includeHiddenApplicationWindows = false
        public static let includePictureInPictureWindows = false
        public static let showTabCounts = false
        public static let showMenuBarItem = false
        public static let showDockIcon = false
        public static let automaticUpdateChecks = true
        public static let firstLaunchCompleted = false
    }

    /// Every user-configurable preference. Restore Defaults iterates this
    /// closed contract; the regression test compares it with every non-internal
    /// key so a future preference cannot silently miss reset integration.
    public static let configurableKeys: Set<Key> = [
        .switcherEnabled,
        .launchAtLogin,
        .shortcut,
        .persistentShortcut,
        .appearanceMode,
        .expandedPreviewDelay,
        .switcherDisplayPlacement,
        .switcherDisplayID,
        .includeOtherSpaces,
        .includeOtherDisplays,
        .includeMinimizedWindows,
        .includeHiddenApplicationWindows,
        .includePictureInPictureWindows,
        .showTabCounts,
        .showMenuBarItem,
        .showDockIcon,
        .automaticUpdateChecks,
    ]

    public static let defaultValues: [String: Any] = [
        Key.switcherEnabled.rawValue: Defaults.switcherEnabled,
        Key.launchAtLogin.rawValue: Defaults.launchAtLogin,
        Key.shortcut.rawValue: Defaults.shortcut.rawValue,
        Key.persistentShortcut.rawValue: Defaults.persistentShortcut?.encoded ?? "",
        Key.appearanceMode.rawValue: Defaults.appearanceMode.rawValue,
        Key.expandedPreviewDelay.rawValue: Defaults.expandedPreviewDelay.rawValue,
        Key.switcherDisplayPlacement.rawValue: Defaults.switcherDisplayPlacement.rawValue,
        // an absent chosen display is the empty string, matching persistentShortcut:
        // the registration domain cannot hold nil
        Key.switcherDisplayID.rawValue: Defaults.switcherDisplayID ?? "",
        Key.includeOtherSpaces.rawValue: Defaults.includeOtherSpaces,
        Key.includeOtherDisplays.rawValue: Defaults.includeOtherDisplays,
        Key.includeMinimizedWindows.rawValue: Defaults.includeMinimizedWindows,
        Key.includeHiddenApplicationWindows.rawValue: Defaults.includeHiddenApplicationWindows,
        Key.includePictureInPictureWindows.rawValue: Defaults.includePictureInPictureWindows,
        Key.showTabCounts.rawValue: Defaults.showTabCounts,
        Key.showMenuBarItem.rawValue: Defaults.showMenuBarItem,
        Key.showDockIcon.rawValue: Defaults.showDockIcon,
        Key.automaticUpdateChecks.rawValue: Defaults.automaticUpdateChecks,
        Key.firstLaunchCompleted.rawValue: Defaults.firstLaunchCompleted,
    ]

    private let defaults: UserDefaults
    private var isRestoringDefaults = false

    @Published public var switcherEnabled: Bool {
        didSet { defaults.set(switcherEnabled, forKey: Key.switcherEnabled.rawValue) }
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }

    @Published public var shortcut: ShortcutSpec {
        didSet { defaults.set(shortcut.rawValue, forKey: Key.shortcut.rawValue) }
    }

    /// nil when the user explicitly leaves Open WindowHop unassigned.
    @Published public var persistentShortcut: PersistentShortcut? {
        didSet { defaults.set(persistentShortcut?.encoded ?? "", forKey: Key.persistentShortcut.rawValue) }
    }

    @Published public var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode.rawValue) }
    }

    @Published public var expandedPreviewDelay: ExpandedPreviewDelay {
        didSet {
            defaults.set(expandedPreviewDelay.rawValue,
                         forKey: Key.expandedPreviewDelay.rawValue)
        }
    }

    @Published public var switcherDisplayPlacement: SwitcherDisplayPlacement {
        didSet {
            defaults.set(switcherDisplayPlacement.rawValue,
                         forKey: Key.switcherDisplayPlacement.rawValue)
        }
    }

    /// nil when no specific display has been chosen. A chosen display that is
    /// currently disconnected keeps its id here, so unplugging a monitor never
    /// destroys the choice.
    @Published public var switcherDisplayID: String? {
        didSet {
            defaults.set(switcherDisplayID ?? "", forKey: Key.switcherDisplayID.rawValue)
        }
    }

    @Published public var includeOtherSpaces: Bool {
        didSet {
            defaults.set(includeOtherSpaces, forKey: Key.includeOtherSpaces.rawValue)
            notifyWindowFiltersChanged()
        }
    }

    @Published public var includeOtherDisplays: Bool {
        didSet {
            defaults.set(includeOtherDisplays, forKey: Key.includeOtherDisplays.rawValue)
            notifyWindowFiltersChanged()
        }
    }

    @Published public var includeMinimizedWindows: Bool {
        didSet {
            defaults.set(includeMinimizedWindows,
                         forKey: Key.includeMinimizedWindows.rawValue)
            notifyWindowFiltersChanged()
        }
    }

    @Published public var includeHiddenApplicationWindows: Bool {
        didSet {
            defaults.set(includeHiddenApplicationWindows,
                         forKey: Key.includeHiddenApplicationWindows.rawValue)
            notifyWindowFiltersChanged()
        }
    }

    @Published public var includePictureInPictureWindows: Bool {
        didSet {
            defaults.set(includePictureInPictureWindows,
                         forKey: Key.includePictureInPictureWindows.rawValue)
            notifyWindowFiltersChanged()
        }
    }

    @Published public var showTabCounts: Bool {
        didSet { defaults.set(showTabCounts, forKey: Key.showTabCounts.rawValue) }
    }

    @Published public var showMenuBarItem: Bool {
        didSet { defaults.set(showMenuBarItem, forKey: Key.showMenuBarItem.rawValue) }
    }

    @Published public var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon.rawValue) }
    }

    @Published public var automaticUpdateChecks: Bool {
        didSet {
            defaults.set(automaticUpdateChecks,
                         forKey: Key.automaticUpdateChecks.rawValue)
        }
    }

    @Published public var firstLaunchCompleted: Bool {
        didSet { defaults.set(firstLaunchCompleted, forKey: Key.firstLaunchCompleted.rawValue) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Registration defaults are not persisted. Capture whether the user
        // explicitly cleared or customized Open WindowHop before registering
        // the new 1.3.1 default so upgrades never overwrite that choice.
        let storedPersistentShortcut = defaults.object(
            forKey: Key.persistentShortcut.rawValue)
        defaults.register(defaults: Preferences.defaultValues)
        switcherEnabled = Self.bool(
            defaults, .switcherEnabled, fallback: Defaults.switcherEnabled)
        launchAtLogin = Self.bool(
            defaults, .launchAtLogin, fallback: Defaults.launchAtLogin)
        shortcut = ShortcutSpec(rawValue: Self.string(defaults, .shortcut) ?? "")
            ?? Defaults.shortcut
        persistentShortcut = Self.persistentShortcut(from: storedPersistentShortcut)
        appearanceMode = AppearanceMode(
            rawValue: Self.string(defaults, .appearanceMode) ?? "")
            ?? Defaults.appearanceMode
        let restoredExpandedPreviewDelay = Self.expandedPreviewDelay(from: defaults)
        expandedPreviewDelay = restoredExpandedPreviewDelay
        defaults.set(restoredExpandedPreviewDelay.rawValue,
                     forKey: Key.expandedPreviewDelay.rawValue)
        switcherDisplayPlacement = SwitcherDisplayPlacement(
            rawValue: Self.string(defaults, .switcherDisplayPlacement) ?? "")
            ?? Defaults.switcherDisplayPlacement
        switcherDisplayID = Self.optionalString(defaults, .switcherDisplayID)
        includeOtherSpaces = Self.bool(
            defaults, .includeOtherSpaces, fallback: Defaults.includeOtherSpaces)
        includeOtherDisplays = Self.bool(
            defaults, .includeOtherDisplays, fallback: Defaults.includeOtherDisplays)
        includeMinimizedWindows = Self.bool(defaults, .includeMinimizedWindows,
                                            fallback: Defaults.includeMinimizedWindows)
        includeHiddenApplicationWindows = Self.bool(
            defaults, .includeHiddenApplicationWindows,
            fallback: Defaults.includeHiddenApplicationWindows)
        includePictureInPictureWindows = Self.bool(
            defaults, .includePictureInPictureWindows,
            fallback: Defaults.includePictureInPictureWindows)
        showTabCounts = Self.bool(
            defaults, .showTabCounts, fallback: Defaults.showTabCounts)
        showMenuBarItem = Self.bool(
            defaults, .showMenuBarItem, fallback: Defaults.showMenuBarItem)
        showDockIcon = Self.bool(
            defaults, .showDockIcon, fallback: Defaults.showDockIcon)
        automaticUpdateChecks = Self.bool(
            defaults, .automaticUpdateChecks,
            fallback: Defaults.automaticUpdateChecks)
        firstLaunchCompleted = Self.bool(
            defaults, .firstLaunchCompleted,
            fallback: Defaults.firstLaunchCompleted)
    }

    private static func bool(_ defaults: UserDefaults, _ key: Key, fallback: Bool) -> Bool {
        guard let value = defaults.object(forKey: key.rawValue) else { return fallback }
        return value as? Bool ?? fallback
    }

    private static func string(_ defaults: UserDefaults, _ key: Key) -> String? {
        defaults.object(forKey: key.rawValue) as? String
    }

    /// An empty stored string means "no value", matching how the registration
    /// domain has to represent nil.
    private static func optionalString(_ defaults: UserDefaults, _ key: Key) -> String? {
        guard let value = string(defaults, key), !value.isEmpty else { return nil }
        return value
    }

    private static func persistentShortcut(from storedValue: Any?) -> PersistentShortcut? {
        // Missing means this installation has never chosen a value and receives
        // the new default. An explicitly stored empty string means the user
        // deliberately cleared the shortcut and must remain unassigned.
        guard let storedValue else { return Defaults.persistentShortcut }
        guard let encoded = storedValue as? String else { return Defaults.persistentShortcut }
        guard !encoded.isEmpty else { return nil }
        return PersistentShortcut(encoded: encoded) ?? Defaults.persistentShortcut
    }

    /// Migrates the 1.1.2 temporary-activation presets to the closest expanded
    /// preview delay. Invalid values use the documented three-second default.
    private static func expandedPreviewDelay(from defaults: UserDefaults) -> ExpandedPreviewDelay {
        if let legacy = string(defaults, .navigationPreviewDelay) {
            defaults.removeObject(forKey: Key.navigationPreviewDelay.rawValue)
            switch legacy {
            case "off": return .off
            case "short": return .oneSecond
            case "long": return .fiveSeconds
            case "standard": return .threeSeconds
            default: return Defaults.expandedPreviewDelay
            }
        }
        if let raw = string(defaults, .expandedPreviewDelay),
           let delay = ExpandedPreviewDelay(rawValue: raw) {
            return delay
        }
        return Defaults.expandedPreviewDelay
    }

    /// Restores every user-configurable value synchronously on the main thread.
    /// SwiftUI publishes after this call returns, so controls and runtime
    /// observers see the complete default set rather than a half-reset form.
    public func restoreDefaults() {
        isRestoringDefaults = true
        defer {
            isRestoringDefaults = false
            notifyWindowFiltersChanged()
        }
        for key in Self.configurableKeys {
            switch key {
            case .switcherEnabled: switcherEnabled = Defaults.switcherEnabled
            case .launchAtLogin: launchAtLogin = Defaults.launchAtLogin
            case .shortcut: shortcut = Defaults.shortcut
            case .persistentShortcut: persistentShortcut = Defaults.persistentShortcut
            case .appearanceMode: appearanceMode = Defaults.appearanceMode
            case .expandedPreviewDelay:
                expandedPreviewDelay = Defaults.expandedPreviewDelay
            case .switcherDisplayPlacement:
                switcherDisplayPlacement = Defaults.switcherDisplayPlacement
            case .switcherDisplayID: switcherDisplayID = Defaults.switcherDisplayID
            case .includeOtherSpaces: includeOtherSpaces = Defaults.includeOtherSpaces
            case .includeOtherDisplays: includeOtherDisplays = Defaults.includeOtherDisplays
            case .includeMinimizedWindows:
                includeMinimizedWindows = Defaults.includeMinimizedWindows
            case .includeHiddenApplicationWindows:
                includeHiddenApplicationWindows = Defaults.includeHiddenApplicationWindows
            case .includePictureInPictureWindows:
                includePictureInPictureWindows = Defaults.includePictureInPictureWindows
            case .showTabCounts: showTabCounts = Defaults.showTabCounts
            case .showMenuBarItem: showMenuBarItem = Defaults.showMenuBarItem
            case .showDockIcon: showDockIcon = Defaults.showDockIcon
            case .automaticUpdateChecks:
                automaticUpdateChecks = Defaults.automaticUpdateChecks
            case .navigationPreviewDelay, .firstLaunchCompleted:
                preconditionFailure("Internal keys must never participate in Restore Defaults")
            }
        }
    }

    public var windowInclusionPolicy: WindowInclusionPolicy {
        WindowInclusionPolicy(
            includeMinimizedWindows: includeMinimizedWindows,
            includeHiddenApplicationWindows: includeHiddenApplicationWindows,
            includePictureInPictureWindows: includePictureInPictureWindows,
            includeOtherSpaces: includeOtherSpaces,
            includeOtherDisplays: includeOtherDisplays)
    }

    private func notifyWindowFiltersChanged() {
        guard !isRestoringDefaults else { return }
        NotificationCenter.default.post(name: Self.windowFiltersDidChange, object: self)
    }
}
