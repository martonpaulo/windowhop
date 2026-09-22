import Carbon.HIToolbox
import XCTest
@testable import WindowHopCore

/// Mapping of `CopySymbolicHotKeys` entries, tested on hand-built dictionaries.
/// The live reader is only smoke-called; nothing writes a system shortcut.
final class SystemShortcutsTests: XCTestCase {
    private func entry(_ keyCode: Int, _ modifiers: Int, enabled: Bool = true) -> [String: Any] {
        [kHISymbolicHotKeyCode as String: NSNumber(value: keyCode),
         kHISymbolicHotKeyModifiers as String: NSNumber(value: modifiers),
         kHISymbolicHotKeyEnabled as String: enabled]
    }

    func testCarbonModifiersMapToEventFlags() {
        XCTAssertEqual(SystemShortcuts.modifiers(fromCarbon: cmdKey), .maskCommand)
        XCTAssertEqual(SystemShortcuts.modifiers(fromCarbon: optionKey), .maskAlternate)
        XCTAssertEqual(SystemShortcuts.modifiers(fromCarbon: controlKey), .maskControl)
        XCTAssertEqual(SystemShortcuts.modifiers(fromCarbon: shiftKey), .maskShift)
        XCTAssertEqual(SystemShortcuts.modifiers(fromCarbon: cmdKey | optionKey | shiftKey),
                       [.maskCommand, .maskAlternate, .maskShift])
    }

    func testEnabledEntriesBecomeChords() {
        let chords = SystemShortcuts.shortcuts(from: [entry(Int(KeyCode.space), cmdKey)])
        XCTAssertEqual(chords, [PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand])])
    }

    func testDisabledAndUnassignedEntriesAreSkipped() {
        let chords = SystemShortcuts.shortcuts(from: [
            entry(Int(KeyCode.space), cmdKey, enabled: false),
            entry(0xFFFF, 0),
            [kHISymbolicHotKeyCode as String: NSNumber(value: 1)], // incomplete
        ])
        XCTAssertEqual(chords, [])
    }

    /// Fn (`kEventKeyModifierFnMask`) is dropped: the tap ignores it when matching.
    func testFnIsDropped() {
        let fnMask = 1 << 17
        let chords = SystemShortcuts.shortcuts(from: [entry(123 /* ← */, controlKey | fnMask)])
        XCTAssertEqual(chords, [PersistentShortcut(keyCode: 123, modifiers: [.maskControl])])
    }

    func testLiveReaderReturns() {
        let chords = SystemShortcuts.enabled()
        XCTAssertTrue(chords.allSatisfy { $0.keyCode != 0xFFFF })
    }
}
