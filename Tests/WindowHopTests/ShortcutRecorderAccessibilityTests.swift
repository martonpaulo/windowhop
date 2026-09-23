import AppKit
import SwiftUI
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// What assistive technology reads from the Open WindowHop recorder: its
    /// purpose (label), the current chord in words or its absence (value), whether
    /// it is recording, and why the last chord was rejected (help). Before issue
    /// #78 the value was nil in every state, recording showed only in the glyph
    /// title, and the validation message was not reachable from the control.
    @MainActor
    final class ShortcutRecorderAccessibilityTests {
        private final class Model: ObservableObject {
            @Published var shortcut: PersistentShortcut? = .optionTab
            @Published var validationMessage: String?
        }

        private struct Host: View {
            @ObservedObject var model: Model

            var body: some View {
                ShortcutRecorderField(
                    shortcut: $model.shortcut,
                    validationMessage: $model.validationMessage,
                    switcherShortcut: .commandTab,
                    systemShortcuts: { [] })
            }
        }

        private static let keyK: Int64 = 40

        private var model: Model!
        private var hosting: NSHostingView<Host>!
        private var window: NSWindow!
        private var control: ShortcutRecorderControl!

        init() throws {
            model = Model()
            hosting = NSHostingView(rootView: Host(model: model))
            hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
            window = NSWindow(
                contentRect: hosting.frame, styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            flushUpdates()
            // unwrapped into a local: assigned straight to the implicitly unwrapped
            // property, #require would infer an optional result and never fail
            let found = try #require(Self.recorder(in: hosting))
            control = found
        }

        isolated deinit {
            window.close()
            control = nil
            window = nil
            hosting = nil
            model = nil
        }

        private static func recorder(in view: NSView) -> ShortcutRecorderControl? {
            if let control = view as? ShortcutRecorderControl { return control }
            return view.subviews.lazy.compactMap(recorder(in:)).first
        }

        private func flushUpdates() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }

        private func sendKey(_ keyCode: Int64, _ modifiers: NSEvent.ModifierFlags = []) throws {
            NSApplication.shared.sendEvent(
                try #require(
                    NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: modifiers,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        characters: "", charactersIgnoringModifiers: "",
                        isARepeat: false, keyCode: UInt16(keyCode))))
            flushUpdates()
        }

        @Test func assignedChordIsSpokenInWords() {
            #expect(control.accessibilityLabel() == "Open WindowHop shortcut")
            #expect(control.title == PersistentShortcut.optionTab.displayString)
            #expect((control.accessibilityValue() as? String) == PersistentShortcut.optionTab.spokenString)
            #expect(control.accessibilityHelp() == nil)
        }

        @Test func clearedRecorderSaysItHasNoChord() {
            model.shortcut = nil
            flushUpdates()
            #expect(control.accessibilityLabel() == "Open WindowHop shortcut")
            #expect((control.accessibilityValue() as? String) == "None")
        }

        @Test func recordingIsExposedWithItsKeysNamedByTheFormatter() {
            control.performClick(nil)
            #expect((control.accessibilityValue() as? String) == "Recording")
            let escape = ShortcutFormatter.spokenKeyName(for: KeyCode.escape)
            let delete = ShortcutFormatter.spokenKeyName(for: KeyCode.delete)
            #expect(control.accessibilityHelp() == "Press a shortcut. \(escape) cancels, \(delete) clears.")
            // the visible prompt uses the formatter's glyphs, not a second copy
            #expect(control.title.contains("\(ShortcutFormatter.keySymbol(for: KeyCode.escape)) cancels"))
            #expect(control.title.contains("\(ShortcutFormatter.keySymbol(for: KeyCode.delete)) clears"))
        }

        @Test func escapeCancelsAndRestoresTheChordValue() throws {
            control.performClick(nil)
            try sendKey(KeyCode.escape)
            #expect((control.accessibilityValue() as? String) == PersistentShortcut.optionTab.spokenString)
            #expect(control.accessibilityHelp() == nil)
        }

        @Test func rejectedChordIsReachableAsTheRecordersHelp() throws {
            control.performClick(nil)
            // no modifier: rejected, and the stored chord is unchanged
            try sendKey(Self.keyK)
            let message = try #require(model.validationMessage)
            #expect(message == PersistentShortcut.ValidationError.needsModifier.explanation)
            #expect(control.accessibilityHelp() == message)
            #expect((control.accessibilityValue() as? String) == PersistentShortcut.optionTab.spokenString)

            // a valid chord clears the error from the control too
            control.performClick(nil)
            try sendKey(Self.keyK, [.control, .option])
            #expect(control.accessibilityHelp() == nil)
            #expect((control.accessibilityValue() as? String) == "Control Option K")
        }
    }
}
