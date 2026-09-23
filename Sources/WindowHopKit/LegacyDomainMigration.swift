import Foundation

/// The one-time copy of WindowHop's settings from the defaults domain of its old
/// bundle identifier, `com.perso.windowhop`, to the current one (#43).
///
/// macOS keys `UserDefaults` to the bundle identifier, so the first launch under
/// the new identifier starts from an empty domain. The app delegate runs
/// this before it creates `Preferences`, whose `PreferencesKeyMigration` then
/// moves any unversioned names that were copied (#111). The old domain is only
/// read and stays in place, so an older build still finds its settings.
///
/// Only names WindowHop owns are copied: every `Preferences.Key`, the
/// unversioned name each one had before #111, the key-migration schema, and the
/// names the caller adds (the Settings window frame). A name the new domain
/// already stores keeps its value. `markerKey` records that the copy ran, even
/// when there was nothing to copy; it is not a setting, so Restore Defaults
/// leaves it alone.
public enum LegacyDomainMigration {
    /// The only place the old identifier may appear.
    public static let legacyDomainName = "com.perso.windowhop"
    public static let markerKey = "preferences.legacyDomainMigrated"

    /// The names this migration copies, besides the caller's extra names.
    public static let ownedNames: Set<String> = Set(
        Preferences.Key.allCases.map(\.rawValue)
            + PreferencesKeyMigration.renamedKeys.map(\.old)
            + [PreferencesKeyMigration.schemaKey])

    /// What to write into the current domain, or nil when the copy already ran.
    /// Always includes the marker when it has not run.
    public static func valuesToCopy(
        legacyDomain: [String: Any]?, currentDomain: [String: Any], extraNames: Set<String> = []
    ) -> [String: Any]? {
        guard currentDomain[markerKey] == nil else { return nil }
        let names = ownedNames.union(extraNames)
        var values: [String: Any] = [:]
        for (name, value) in legacyDomain ?? [:]
        where names.contains(name) && currentDomain[name] == nil {
            values[name] = value
        }
        values[markerKey] = true
        return values
    }

    /// Runs the copy once for `defaults`, whose persistent domain is `currentDomain`.
    public static func migrate(
        _ defaults: UserDefaults, currentDomain: [String: Any], legacyDomain: [String: Any]?,
        extraNames: Set<String> = []
    ) {
        guard
            let values = valuesToCopy(
                legacyDomain: legacyDomain, currentDomain: currentDomain, extraNames: extraNames)
        else { return }
        for (name, value) in values {
            defaults.set(value, forKey: name)
        }
    }
}
