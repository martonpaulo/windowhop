import Carbon.HIToolbox
import Foundation
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

/// Mapping of `CopySymbolicHotKeys` entries, tested on hand-built dictionaries.
/// The live reader is only smoke-called; nothing writes a system shortcut.
/// The Carbon call runs on the main thread, where the app and XCTest called it.
@MainActor
struct SystemShortcutsTests {
    private func entry(_ keyCode: Int, _ modifiers: Int, enabled: Bool = true) -> [String: Any] {
        [
            kHISymbolicHotKeyCode as String: NSNumber(value: keyCode),
            kHISymbolicHotKeyModifiers as String: NSNumber(value: modifiers),
            kHISymbolicHotKeyEnabled as String: enabled,
        ]
    }

    @Test func carbonModifiersMapToEventFlags() {
        #expect(SystemShortcuts.modifiers(fromCarbon: cmdKey) == .maskCommand)
        #expect(SystemShortcuts.modifiers(fromCarbon: optionKey) == .maskAlternate)
        #expect(SystemShortcuts.modifiers(fromCarbon: controlKey) == .maskControl)
        #expect(SystemShortcuts.modifiers(fromCarbon: shiftKey) == .maskShift)
        #expect(
            SystemShortcuts.modifiers(fromCarbon: cmdKey | optionKey | shiftKey) == [
                .maskCommand, .maskAlternate, .maskShift,
            ])
    }

    @Test func enabledEntriesBecomeChords() {
        let chords = SystemShortcuts.shortcuts(from: [entry(Int(KeyCode.space), cmdKey)])
        #expect(chords == [PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand])])
    }

    @Test func disabledAndUnassignedEntriesAreSkipped() {
        let chords = SystemShortcuts.shortcuts(from: [
            entry(Int(KeyCode.space), cmdKey, enabled: false),
            entry(0xFFFF, 0),
            [kHISymbolicHotKeyCode as String: NSNumber(value: 1)],  // incomplete
        ])
        #expect(chords == [])
    }

    /// Fn (`kEventKeyModifierFnMask`) is dropped: the tap ignores it when matching.
    @Test func fnIsDropped() {
        let fnMask = 1 << 17
        let leftArrow = 123
        let chords = SystemShortcuts.shortcuts(from: [entry(leftArrow, controlKey | fnMask)])
        #expect(chords == [PersistentShortcut(keyCode: 123, modifiers: [.maskControl])])
    }

    @Test func liveReaderReturns() {
        let chords = SystemShortcuts.enabled()
        #expect(chords.allSatisfy { $0.keyCode != 0xFFFF })
    }
}
