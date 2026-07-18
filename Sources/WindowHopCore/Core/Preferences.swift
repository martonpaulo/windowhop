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

/// All WindowHop settings with their defaults. This observable model is the
/// single runtime source of truth; UserDefaults is only its persistence layer.
/// The store is injectable for deterministic migration and persistence tests.
public final class Preferences: ObservableObject {
    public static let shared = Preferences()

    public enum Key: String, CaseIterable {
        case switcherEnabled
        case launchAtLogin
        case shortcut
        case persistentShortcut
        case appearanceMode
        case includeOtherSpaces
        case includeOtherDisplays
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
        Key.includeOtherSpaces.rawValue: true,
        Key.includeOtherDisplays.rawValue: true,
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

    @Published public var includeOtherSpaces: Bool {
        didSet { defaults.set(includeOtherSpaces, forKey: Key.includeOtherSpaces.rawValue) }
    }

    @Published public var includeOtherDisplays: Bool {
        didSet { defaults.set(includeOtherDisplays, forKey: Key.includeOtherDisplays.rawValue) }
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
        includeOtherSpaces = Self.bool(defaults, .includeOtherSpaces, fallback: true)
        includeOtherDisplays = Self.bool(defaults, .includeOtherDisplays, fallback: true)
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
}
