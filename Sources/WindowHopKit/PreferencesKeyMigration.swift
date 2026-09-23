import Foundation

/// The one-time move of every WindowHop-owned setting from its unversioned
/// `UserDefaults` name to its versioned `<name>.v1` name (#111).
///
/// It runs from `Preferences.init(defaults:)` before the first read, so no
/// consumer ever sees an empty store. `preferences.schema` in the same domain
/// records that it ran; a later run does nothing. For each key it copies a stored
/// value only when that value decodes under the key's current type, then removes
/// the old name. An invalid value is dropped, so the key falls back to
/// `Preferences.Defaults` exactly as an invalid value under the new name would.
/// The new names are not checked first: the registration domain answers for
/// them in every process, and the schema guard already makes this run once.
///
/// Two keys keep their names. `SUEnableAutomaticChecks` belongs to Sparkle, which
/// reads and writes it under that exact name (and `Support/Info.plist` declares
/// it). `navigationPreviewDelay` exists only as the 1.1.2 name that the
/// expanded-preview migration reads and removes.
public enum PreferencesKeyMigration {
    /// The schema this build writes. Raise it together with a new step.
    public static let currentSchema = 1
    public static let schemaKey = "preferences.schema"
    static let versionSuffix = ".v1"

    /// Every key that moved, with the name it had before schema 1.
    public static let renamedKeys: [(old: String, new: Preferences.Key)] =
        Preferences.Key.allCases.compactMap { key in
            guard key.rawValue.hasSuffix(versionSuffix) else { return nil }
            return (String(key.rawValue.dropLast(versionSuffix.count)), key)
        }

    /// Runs the migration once per defaults domain.
    public static func migrate(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: schemaKey) < currentSchema else { return }
        for (old, key) in renamedKeys {
            guard let value = defaults.object(forKey: old) else { continue }
            if isValid(value, for: key) {
                defaults.set(value, forKey: key.rawValue)
            }
            defaults.removeObject(forKey: old)
        }
        defaults.set(currentSchema, forKey: schemaKey)
    }

    /// Whether `value` decodes under `key`'s current type, with the same rules
    /// `Preferences` applies when it reads the key.
    static func isValid(_ value: Any, for key: Preferences.Key) -> Bool {
        switch key {
        case .switcherEnabled, .launchAtLogin, .includeOtherSpaces, .includeOtherDisplays,
             .includeMinimizedWindows, .includeHiddenApplicationWindows,
             .includePictureInPictureWindows, .showTabCounts, .showMenuBarItem, .showDockIcon,
             .automaticUpdateChecks, .firstLaunchCompleted:
            return value is Bool
        case .shortcut:
            return (value as? String).flatMap(ShortcutSpec.init(rawValue:)) != nil
        case .persistentShortcut:
            // an empty string is an explicit "unassigned", a real choice to keep
            guard let encoded = value as? String else { return false }
            return encoded.isEmpty || PersistentShortcut(encoded: encoded) != nil
        case .appearanceMode:
            return (value as? String).flatMap(AppearanceMode.init(rawValue:)) != nil
        case .expandedPreviewDelay:
            return (value as? String).flatMap(ExpandedPreviewDelay.init(rawValue:)) != nil
        case .switcherRevealDelay:
            return (value as? String).flatMap(SwitcherRevealDelay.init(rawValue:)) != nil
        case .switcherDisplayPlacement:
            return (value as? String).flatMap(SwitcherDisplayPlacement.init(rawValue:)) != nil
        case .switcherDisplayID:
            return value is String
        case .navigationPreviewDelay:
            return value is String
        }
    }
}
