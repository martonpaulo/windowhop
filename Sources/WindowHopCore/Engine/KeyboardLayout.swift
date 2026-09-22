import Carbon.HIToolbox
import Foundation

/// The live keyboard layout as a `KeyLabelSource`: the character a physical key
/// types on the current input source, read on demand (no cache, no observer).
///
/// Text Input Sources are main-thread only on current macOS, so an off-main
/// call returns nil and `ShortcutFormatter` falls back to the ANSI table.
public struct KeyboardLayout: KeyLabelSource {
    public static let current = KeyboardLayout()

    /// Posted on `DistributedNotificationCenter` when the user selects another
    /// input source. Labels shown on screen refresh on it; the stored binding
    /// never changes. AltTab refreshes on the same notification
    /// (`317a485b:src/logic/events/InputSourceEvents.swift`).
    public static let selectionDidChangeNotification =
        Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    public func character(forKeyCode keyCode: UInt16) -> String? {
        guard Thread.isMainThread, let source = Self.currentLayoutSource() else { return nil }
        return Self.character(forKeyCode: keyCode, in: source)
    }

    /// The selected input source when it carries layout data; otherwise (an
    /// input method such as Japanese Kana) the ASCII-capable layout it types with.
    private static func currentLayoutSource() -> TISInputSource? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           layoutData(of: source) != nil {
            return source
        }
        return TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
    }

    private static func layoutData(of source: TISInputSource) -> CFData? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// The unmodified character `keyCode` types in `source`'s layout.
    ///
    /// Options take `kUCKeyTranslateNoDeadKeysMask` (the option *mask*, 1 << 0),
    /// never `kUCKeyTranslateNoDeadKeysBit` (the bit index 0, which sets no
    /// option); see `UnicodeUtilities.h`. With it, a dead key such as French ^
    /// names itself and no dead-key state is carried between calls. Measured on
    /// macOS 26: with `kUCKeyActionDisplay` the French ^ key already returns "^"
    /// either way, so the mask is the documented guarantee, not a visible fix.
    /// The result is built from all returned UTF-16 units, so multi-unit
    /// characters stay whole.
    static func character(forKeyCode keyCode: UInt16, in source: TISInputSource) -> String? {
        guard let data = layoutData(of: source), let bytes = CFDataGetBytePtr(data) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var deadKeyState: UInt32 = 0
            var length = 0
            var units = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                units.count, &length, &units)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: units, count: length)
        }
    }

    /// An installed keyboard layout by input-source identifier (for example
    /// `com.apple.keylayout.German`), read without selecting or enabling it.
    static func installedLayout(identifier: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue()
                as? [TISInputSource] else { return nil }
        return list.first
    }
}
