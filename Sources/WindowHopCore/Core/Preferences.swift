import Foundation

/// All WindowHop settings with their defaults. UserDefaults-backed; the store is injectable for tests.
public final class Preferences {
    public static let shared = Preferences()

    public enum Key: String, CaseIterable {
        case switcherEnabled
        case launchAtLogin
        case shortcut
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
        Key.includeOtherSpaces.rawValue: true,
        Key.includeOtherDisplays.rawValue: true,
        Key.showTabCounts.rawValue: true,
        Key.showMenuBarItem.rawValue: false,
        Key.showDockIcon.rawValue: false,
        Key.firstLaunchCompleted.rawValue: false,
    ]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Preferences.defaultValues)
    }

    public var switcherEnabled: Bool {
        get { defaults.bool(forKey: Key.switcherEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.switcherEnabled.rawValue) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }

    public var shortcut: ShortcutSpec {
        get { ShortcutSpec(rawValue: defaults.string(forKey: Key.shortcut.rawValue) ?? "") ?? .commandTab }
        set { defaults.set(newValue.rawValue, forKey: Key.shortcut.rawValue) }
    }

    public var includeOtherSpaces: Bool {
        get { defaults.bool(forKey: Key.includeOtherSpaces.rawValue) }
        set { defaults.set(newValue, forKey: Key.includeOtherSpaces.rawValue) }
    }

    public var includeOtherDisplays: Bool {
        get { defaults.bool(forKey: Key.includeOtherDisplays.rawValue) }
        set { defaults.set(newValue, forKey: Key.includeOtherDisplays.rawValue) }
    }

    public var showTabCounts: Bool {
        get { defaults.bool(forKey: Key.showTabCounts.rawValue) }
        set { defaults.set(newValue, forKey: Key.showTabCounts.rawValue) }
    }

    public var showMenuBarItem: Bool {
        get { defaults.bool(forKey: Key.showMenuBarItem.rawValue) }
        set { defaults.set(newValue, forKey: Key.showMenuBarItem.rawValue) }
    }

    public var showDockIcon: Bool {
        get { defaults.bool(forKey: Key.showDockIcon.rawValue) }
        set { defaults.set(newValue, forKey: Key.showDockIcon.rawValue) }
    }

    public var firstLaunchCompleted: Bool {
        get { defaults.bool(forKey: Key.firstLaunchCompleted.rawValue) }
        set { defaults.set(newValue, forKey: Key.firstLaunchCompleted.rawValue) }
    }
}
