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
        case includeOtherSpaces
        case includeOtherDisplays
        case includeMinimizedWindows
        case includeHiddenApplicationWindows
        case includePictureInPictureWindows
        case showTabCounts
        case showMenuBarItem
        case showDockIcon
        case firstLaunchCompleted
    }

    public static let defaultValues: [String: Any] = [
        Key.switcherEnabled.rawValue: true,
        Key.launchAtLogin.rawValue: true,
        Key.shortcut.rawValue: ShortcutSpec.commandTab.rawValue,
        // unassigned by default: assigning a global chord must be a deliberate choice
        Key.persistentShortcut.rawValue: "",
        Key.appearanceMode.rawValue: AppearanceMode.appIcons.rawValue,
        Key.expandedPreviewDelay.rawValue: ExpandedPreviewDelay.threeSeconds.rawValue,
        Key.includeOtherSpaces.rawValue: true,
        Key.includeOtherDisplays.rawValue: true,
        Key.includeMinimizedWindows.rawValue: false,
        Key.includeHiddenApplicationWindows.rawValue: false,
        Key.includePictureInPictureWindows.rawValue: false,
        Key.showTabCounts.rawValue: true,
        Key.showMenuBarItem.rawValue: false,
        Key.showDockIcon.rawValue: false,
        Key.firstLaunchCompleted.rawValue: false,
    ]

    private let defaults: UserDefaults

    @Published public var switcherEnabled: Bool {
        didSet { defaults.set(switcherEnabled, forKey: Key.switcherEnabled.rawValue) }
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }

    @Published public var shortcut: ShortcutSpec {
        didSet { defaults.set(shortcut.rawValue, forKey: Key.shortcut.rawValue) }
    }

    /// nil when unassigned (the default).
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

    @Published public var firstLaunchCompleted: Bool {
        didSet { defaults.set(firstLaunchCompleted, forKey: Key.firstLaunchCompleted.rawValue) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Preferences.defaultValues)
        switcherEnabled = Self.bool(defaults, .switcherEnabled, fallback: true)
        launchAtLogin = Self.bool(defaults, .launchAtLogin, fallback: true)
        shortcut = ShortcutSpec(rawValue: Self.string(defaults, .shortcut) ?? "") ?? .commandTab
        persistentShortcut = PersistentShortcut(
            encoded: Self.string(defaults, .persistentShortcut) ?? "")
        appearanceMode = AppearanceMode(
            rawValue: Self.string(defaults, .appearanceMode) ?? "") ?? .appIcons
        let restoredExpandedPreviewDelay = Self.expandedPreviewDelay(from: defaults)
        expandedPreviewDelay = restoredExpandedPreviewDelay
        defaults.set(restoredExpandedPreviewDelay.rawValue,
                     forKey: Key.expandedPreviewDelay.rawValue)
        includeOtherSpaces = Self.bool(defaults, .includeOtherSpaces, fallback: true)
        includeOtherDisplays = Self.bool(defaults, .includeOtherDisplays, fallback: true)
        includeMinimizedWindows = Self.bool(defaults, .includeMinimizedWindows,
                                            fallback: false)
        includeHiddenApplicationWindows = Self.bool(
            defaults, .includeHiddenApplicationWindows, fallback: false)
        includePictureInPictureWindows = Self.bool(
            defaults, .includePictureInPictureWindows, fallback: false)
        showTabCounts = Self.bool(defaults, .showTabCounts, fallback: true)
        showMenuBarItem = Self.bool(defaults, .showMenuBarItem, fallback: false)
        showDockIcon = Self.bool(defaults, .showDockIcon, fallback: false)
        firstLaunchCompleted = Self.bool(defaults, .firstLaunchCompleted, fallback: false)
    }

    private static func bool(_ defaults: UserDefaults, _ key: Key, fallback: Bool) -> Bool {
        guard let value = defaults.object(forKey: key.rawValue) else { return fallback }
        return value as? Bool ?? fallback
    }

    private static func string(_ defaults: UserDefaults, _ key: Key) -> String? {
        defaults.object(forKey: key.rawValue) as? String
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
            default: return .threeSeconds
            }
        }
        if let raw = string(defaults, .expandedPreviewDelay),
           let delay = ExpandedPreviewDelay(rawValue: raw) {
            return delay
        }
        return .threeSeconds
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
        NotificationCenter.default.post(name: Self.windowFiltersDidChange, object: self)
    }
}
