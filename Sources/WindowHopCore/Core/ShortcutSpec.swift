import CoreGraphics
import Foundation

/// The switcher trigger: a hold-modifier plus the Tab key.
/// The session stays alive while the hold-modifier is down; adding Shift reverses direction.
/// Only modifier+Tab chords are offered because the hold-to-cycle, release-to-activate
/// interaction requires a held modifier distinct from Shift.
public enum ShortcutSpec: String, CaseIterable, Identifiable {
    case commandTab
    case optionTab
    case controlTab

    public var id: String { rawValue }

    public var holdModifier: CGEventFlags {
        switch self {
        case .commandTab: return .maskCommand
        case .optionTab: return .maskAlternate
        case .controlTab: return .maskControl
        }
    }

    public var displayName: String {
        switch self {
        case .commandTab: return "⌘ Tab"
        case .optionTab: return "⌥ Tab"
        case .controlTab: return "⌃ Tab"
        }
    }
}

/// Virtual key codes used by the event tap (from Carbon's Events.h, stable since classic Mac OS).
public enum KeyCode {
    public static let tab: Int64 = 48
    public static let space: Int64 = 49
    public static let returnKey: Int64 = 36
    public static let keypadEnter: Int64 = 76
    public static let escape: Int64 = 53
    public static let delete: Int64 = 51
    public static let forwardDelete: Int64 = 117
    public static let leftArrow: Int64 = 123
    public static let rightArrow: Int64 = 124
    public static let downArrow: Int64 = 125
    public static let upArrow: Int64 = 126
}
