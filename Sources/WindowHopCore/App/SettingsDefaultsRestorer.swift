import Foundation

/// Coordinates Restore Defaults with the one preference whose authoritative
/// state also lives outside UserDefaults (the macOS login item). The external
/// operation happens first; if it fails, no preference is changed.
public struct SettingsDefaultsRestorer {
    private let preferences: Preferences
    private let setLoginItem: (Bool) -> Bool
    private let applyAutomaticUpdateChecks: (Bool) -> Void

    public static let shared = SettingsDefaultsRestorer(
        preferences: .shared,
        setLoginItem: LoginItem.set,
        applyAutomaticUpdateChecks: {
            UpdateManager.shared.automaticallyChecksForUpdates = $0
        })

    init(preferences: Preferences,
         setLoginItem: @escaping (Bool) -> Bool,
         applyAutomaticUpdateChecks: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.setLoginItem = setLoginItem
        self.applyAutomaticUpdateChecks = applyAutomaticUpdateChecks
    }

    @discardableResult
    public func restore() -> Bool {
        guard setLoginItem(Preferences.Defaults.launchAtLogin) else { return false }
        preferences.restoreDefaults()
        applyAutomaticUpdateChecks(Preferences.Defaults.automaticUpdateChecks)
        return true
    }
}
