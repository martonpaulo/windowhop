import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The enabled macOS keyboard shortcuts (System Settings → Keyboard → Keyboard
/// Shortcuts), read through the public, read-only `CopySymbolicHotKeys`
/// (HIToolbox `CarbonEvents.h`). Read on demand when Settings captures a chord:
/// no cache, no observer, and nothing is ever written — WindowHop never
/// disables or changes a system shortcut.
public enum SystemShortcuts {
    public static func enabled() -> [PersistentShortcut] {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return shortcuts(from: entries)
    }

    /// Enabled entries with a real key code, as chords. The Fn bit is dropped:
    /// the tap ignores Fn when matching, so a recorded chord would take over the
    /// Fn variant too (and F-keys and arrows carry Fn by themselves).
    static func shortcuts(from entries: [[String: Any]]) -> [PersistentShortcut] {
        entries.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let keyCode = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.int64Value,
                  keyCode != 0xFFFF,
                  let carbon = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.intValue
            else { return nil }
            return PersistentShortcut(keyCode: keyCode, modifiers: modifiers(fromCarbon: carbon))
        }
    }

    static func modifiers(fromCarbon carbon: Int) -> CGEventFlags {
        var flags = CGEventFlags()
        if carbon & cmdKey != 0 { flags.insert(.maskCommand) }
        if carbon & optionKey != 0 { flags.insert(.maskAlternate) }
        if carbon & controlKey != 0 { flags.insert(.maskControl) }
        if carbon & shiftKey != 0 { flags.insert(.maskShift) }
        return flags
    }
}
