import AppKit
import SwiftUI
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// SwiftUI keeps one native recorder alive across updates, so its validation
    /// must follow the currently selected switcher shortcut rather than the one
    /// that existed when the control was created. Recording itself is bound to the
    /// recorder's window: it must end on close, resign-key and detach.
    @MainActor
    final class ShortcutRecorderFieldTests {
        /// Isolated test state: these tests never touch the app's `Preferences`.
        private final class Model: ObservableObject {
            @Published var switcherShortcut: ShortcutSpec = .commandTab
            @Published var shortcut: PersistentShortcut?
            @Published var validationMessage: String?
            /// Every value the field forwarded through `onRecordingChanged`.
            var forwardedRecording: [Bool] = []
            /// The fixture standing in for the machine's enabled macOS shortcuts.
            var systemShortcuts: [PersistentShortcut] = []
            /// The answer the injected confirmation gives (true = Use Anyway).
            var confirmationAnswer = false
            /// Every chord the field asked to confirm.
            var confirmationRequests: [PersistentShortcut] = []
        }

        private struct Host: View {
            @ObservedObject var model: Model

            var body: some View {
                ShortcutRecorderField(
                    shortcut: $model.shortcut,
                    validationMessage: $model.validationMessage,
                    switcherShortcut: model.switcherShortcut,
                    onRecordingChanged: { model.forwardedRecording.append($0) },
                    systemShortcuts: { model.systemShortcuts },
                    confirmSystemShortcut: { captured, _, completion in
                        model.confirmationRequests.append(captured)
                        completion(model.confirmationAnswer)
                    })
            }
        }

        /// Every recording-state transition the control reported, in order.
        private final class Transitions {
            var values: [Bool] = []
        }

        private static let keyK: Int64 = 40
        private static let keyJ: Int64 = 38

        private var model: Model!
        private var hosting: NSHostingView<Host>!
        private var window: NSWindow!

        init() {
            model = Model()
            hosting = NSHostingView(rootView: Host(model: model))
            hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
            // Retained like the Settings window, so closing it never detaches the
            // recorder by itself. Never ordered on screen.
            window = makeRetainedWindow(frame: hosting.frame)
            window.contentView = hosting
            flushUpdates()
        }

        isolated deinit {
            window.close()
            window = nil
            hosting = nil
            model = nil
        }

        private func makeRetainedWindow(frame: NSRect) -> NSWindow {
            let window = NSWindow(
                contentRect: frame, styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        }

        /// Lets SwiftUI apply the pending update to the existing native control.
        private func flushUpdates() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }

        private func recorder() throws -> ShortcutRecorderControl {
            func search(_ view: NSView) -> ShortcutRecorderControl? {
                if let control = view as? ShortcutRecorderControl { return control }
                for subview in view.subviews {
                    if let found = search(subview) { return found }
                }
                return nil
            }
            return try #require(search(hosting), "the recorder control is not in the hierarchy")
        }

        private func chord(_ modifiers: CGEventFlags) -> PersistentShortcut {
            PersistentShortcut(keyCode: KeyCode.tab, modifiers: modifiers)
        }

        private func keyEvent(
            _ keyCode: Int64, _ modifiers: NSEvent.ModifierFlags = [],
            for target: NSWindow? = nil
        ) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: (target ?? window).windowNumber, context: nil,
                    characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: UInt16(keyCode)))
        }

        /// Delivers a real key-down through `NSApplication.sendEvent(_:)`, the
        /// dispatch path the recorder's local monitor observes.
        private func sendKey(
            _ keyCode: Int64, _ modifiers: NSEvent.ModifierFlags = [],
            to target: NSWindow? = nil
        ) throws {
            NSApplication.shared.sendEvent(try keyEvent(keyCode, modifiers, for: target))
        }

        /// Starts recording and collects every transition of the recording state.
        private func startRecording(_ control: ShortcutRecorderControl) -> Transitions {
            let transitions = Transitions()
            control.onRecordingChanged = { transitions.values.append($0) }
            control.performClick(nil)
            #expect(control.isInterceptingKeys, "recording installs the key monitor")
            return transitions
        }

        /// Once recording ended, no monitor is left and a key for the recorder's
        /// window reaches neither callback.
        private func assertNoLongerCapturing(
            _ control: ShortcutRecorderControl,
            sourceLocation: SourceLocation = #_sourceLocation
        ) throws {
            var callbacks = 0
            control.onCapture = { _ in callbacks += 1 }
            control.onClear = { callbacks += 1 }

            try sendKey(Self.keyJ, [.control, .option])
            try sendKey(KeyCode.delete)

            #expect(!control.isInterceptingKeys, "no key monitor survives", sourceLocation: sourceLocation)
            #expect(callbacks == 0, "no capture callback survives", sourceLocation: sourceLocation)
            #expect(
                control.title == "Record Shortcut…", "the idle title is back",
                sourceLocation: sourceLocation)
        }

        /// The recorder has a fixed width in Settings › Shortcuts, so every title it
        /// shows must fit inside it: the recording prompt, the idle prompt and the
        /// widest chord. The recording prompt used to be cut off (#131).
        @Test func recorderWidthHoldsEveryTitle() throws {
            let control = try recorder()
            #expect(control.intrinsicContentSize.width <= DesignTokens.settingsRecorderWidth)

            model.shortcut = PersistentShortcut(
                keyCode: 111, modifiers: [.maskControl, .maskAlternate, .maskShift, .maskCommand])
            flushUpdates()
            #expect(control.intrinsicContentSize.width <= DesignTokens.settingsRecorderWidth)

            _ = startRecording(control)
            #expect(control.intrinsicContentSize.width <= DesignTokens.settingsRecorderWidth)
        }

        /// Positive control: a key sent through AppKit's dispatch reaches the
        /// recorder's monitor in the test process.
        @Test func sentChordIsCapturedAndEndsRecording() throws {
            let control = try recorder()
            let transitions = startRecording(control)

            try sendKey(Self.keyK, [.control, .option])

            #expect(
                model.shortcut == PersistentShortcut(keyCode: Self.keyK, modifiers: [.maskControl, .maskAlternate]))
            #expect(model.validationMessage == nil)
            #expect(transitions.values == [true, false])
            #expect(!control.isInterceptingKeys)
        }

        @Test func closingRetainedWindowEndsRecording() throws {
            let control = try recorder()
            let transitions = startRecording(control)

            window.close()

            #expect(control.window != nil, "a retained window keeps the control attached")
            #expect(transitions.values == [true, false])
            try assertNoLongerCapturing(control)
            #expect(model.shortcut == nil)
        }

        @Test func resignKeyEndsRecording() throws {
            let control = try recorder()
            let transitions = startRecording(control)

            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

            #expect(transitions.values == [true, false])
            try assertNoLongerCapturing(control)
            #expect(model.shortcut == nil)
        }

        @Test func anotherWindowResigningKeyDoesNotEndRecording() throws {
            let control = try recorder()
            let other = makeRetainedWindow(frame: .zero)
            defer { other.close() }
            let transitions = startRecording(control)

            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)

            #expect(transitions.values == [true])
            #expect(control.isInterceptingKeys)
        }

        @Test func keyEventsForOtherWindowsAreNotCaptured() throws {
            let control = try recorder()
            let other = makeRetainedWindow(frame: .zero)
            defer { other.close() }
            let transitions = startRecording(control)
            var callbacks = 0
            control.onCapture = { _ in callbacks += 1 }
            control.onClear = { callbacks += 1 }

            try sendKey(Self.keyK, [.control, .option], to: other)
            try sendKey(KeyCode.escape, to: other)
            let foreign = try keyEvent(Self.keyK, [.control, .option], for: other)

            #expect(
                control.handleRecordingKeyDown(foreign) === foreign,
                "another window's key event is passed on unchanged")
            #expect(callbacks == 0)
            #expect(transitions.values == [true], "recording continues in its own window")
            #expect(model.shortcut == nil)
        }

        @Test func detachEndsRecordingOnce() throws {
            let control = try recorder()
            let transitions = startRecording(control)

            hosting.removeFromSuperview()

            #expect(control.window == nil)
            #expect(!control.isInterceptingKeys)
            #expect(transitions.values == [true, false])
            window.close()
            #expect(transitions.values == [true, false], "a later close does not end it twice")
        }

        @Test func captureEndsRecordingExactlyOnce() throws {
            let control = try recorder()
            let transitions = startRecording(control)

            try sendKey(Self.keyK, [.control, .option])
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            window.close()

            #expect(transitions.values == [true, false])
        }

        @Test func captureAfterPrimaryChangeRejectsTheNewPrimaryChord() throws {
            let control = try recorder()
            model.switcherShortcut = .optionTab
            flushUpdates()
            #expect(try recorder() === control, "SwiftUI must reuse the native control")

            control.onCapture?(chord(.maskAlternate))

            #expect(model.shortcut == nil, "a conflicting chord must not be persisted")
            #expect(
                model.validationMessage == PersistentShortcut.ValidationError.conflictsWithSwitcherShortcut.explanation)
        }

        @Test func chordConflictingOnlyWithTheFormerPrimaryIsAccepted() throws {
            let control = try recorder()
            model.switcherShortcut = .optionTab
            flushUpdates()

            control.onCapture?(chord(.maskCommand))

            #expect(model.shortcut == chord(.maskCommand))
            #expect(model.validationMessage == nil)
        }

        @Test func validCaptureClearsAnEarlierValidationMessage() throws {
            let control = try recorder()
            control.onCapture?(chord(.maskCommand))
            #expect(model.validationMessage != nil)

            control.onCapture?(chord([.maskControl, .maskShift]))

            #expect(model.shortcut == chord([.maskControl, .maskShift]))
            #expect(model.validationMessage == nil)
        }

        @Test func clearResetsShortcutAndMessageThroughCurrentBindings() throws {
            let control = try recorder()
            control.onCapture?(chord(.maskControl))
            model.switcherShortcut = .optionTab
            flushUpdates()

            control.onClear?()

            #expect(model.shortcut == nil)
            #expect(model.validationMessage == nil)
        }

        /// A real Escape through the recorder's monitor ends recording without
        /// reaching either callback; the next chord is no longer captured.
        @Test func escapeCancelsRecordingWithoutSaving() throws {
            let installed = PersistentShortcut(keyCode: Self.keyK, modifiers: [.maskControl, .maskAlternate])
            model.shortcut = installed
            flushUpdates()
            let control = try recorder()
            let transitions = startRecording(control)
            var callbacks = 0
            let bindingCapture = control.onCapture
            let bindingClear = control.onClear
            control.onCapture = {
                callbacks += 1
                bindingCapture?($0)
            }
            control.onClear = {
                callbacks += 1
                bindingClear?()
            }

            try sendKey(KeyCode.escape)

            #expect(callbacks == 0, "Escape reaches neither capture nor clear")
            #expect(model.shortcut == installed, "the installed shortcut is kept")
            #expect(model.validationMessage == nil)
            #expect(transitions.values == [true, false])
            #expect(!control.isInterceptingKeys, "no key monitor survives the cancellation")
            #expect(control.title == installed.displayString)

            try sendKey(Self.keyJ, [.control, .option])
            let later = try keyEvent(Self.keyJ, [.control, .option])

            #expect(
                control.handleRecordingKeyDown(later) === later,
                "a later chord is passed on, not swallowed")
            #expect(callbacks == 0, "a later chord is not captured")
            #expect(model.shortcut == installed)
            #expect(model.validationMessage == nil)
            #expect(transitions.values == [true, false])
        }

        // MARK: - Conflicts with macOS and standard app commands (#56)

        private static let commandSpace = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand])
        private static let controlOptionK = PersistentShortcut(
            keyCode: keyK, modifiers: [.maskControl, .maskAlternate])

        @Test func standardAppCommandIsRejectedWithItsName() throws {
            model.shortcut = Self.controlOptionK
            flushUpdates()
            let control = try recorder()

            control.onCapture?(PersistentShortcut(keyCode: 12, modifiers: [.maskCommand]))  // 12 is Q

            #expect(model.shortcut == Self.controlOptionK, "nothing is persisted")
            #expect(
                model.validationMessage
                    == "⌘Q is the Quit command in apps. Choose a combination that isn't a standard app command.")
            #expect(model.confirmationRequests == [])
        }

        @Test func systemShortcutCancelKeepsThePreviousChord() throws {
            model.shortcut = Self.controlOptionK
            model.systemShortcuts = [Self.commandSpace]
            model.confirmationAnswer = false
            flushUpdates()
            let control = try recorder()

            control.onCapture?(Self.commandSpace)

            #expect(model.confirmationRequests == [Self.commandSpace])
            #expect(model.shortcut == Self.controlOptionK, "Cancel persists nothing")
            #expect(model.validationMessage == nil)
        }

        @Test func systemShortcutUseAnywayPersists() throws {
            model.systemShortcuts = [Self.commandSpace]
            model.confirmationAnswer = true
            model.validationMessage = "an earlier rejection"
            flushUpdates()
            let control = try recorder()

            control.onCapture?(Self.commandSpace)

            #expect(model.confirmationRequests == [Self.commandSpace])
            #expect(model.shortcut == Self.commandSpace)
            #expect(model.validationMessage == nil)
        }

        @Test func reRecordingTheStoredSystemChordNeedsNoConfirmation() throws {
            model.shortcut = Self.commandSpace
            model.systemShortcuts = [Self.commandSpace]
            flushUpdates()
            let control = try recorder()

            control.onCapture?(Self.commandSpace)

            #expect(model.confirmationRequests == [])
            #expect(model.shortcut == Self.commandSpace)
        }

        /// Selecting another input source relabels the recorded key while the
        /// recorder is in a window, and never changes the binding. A private center
        /// stands in for the distributed one, so no system-wide notification is posted.
        @Test func inputSourceChangeRefreshesTheLabelOnlyWhileInAWindow() {
            struct Fixture: KeyLabelSource {
                let character: String
                func character(forKeyCode keyCode: UInt16) -> String? { keyCode == 6 ? character : nil }
            }
            defer { ShortcutFormatter.keyLabels = ANSIKeyLabels() }
            let center = NotificationCenter()
            let control = ShortcutRecorderControl()
            control.inputSourceNotificationCenter = center
            let host = makeRetainedWindow(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
            defer { host.close() }
            let recorded = PersistentShortcut(keyCode: 6, modifiers: [.maskAlternate])
            ShortcutFormatter.keyLabels = Fixture(character: "z")
            control.shortcut = recorded
            host.contentView?.addSubview(control)
            #expect(control.title == "⌥Z")

            ShortcutFormatter.keyLabels = Fixture(character: "y")
            center.post(name: KeyboardLayout.selectionDidChangeNotification, object: nil)

            #expect(control.title == "⌥Y")
            #expect((control.accessibilityValue() as? String) == "Option Y")
            #expect(control.shortcut == recorded, "the binding is unchanged")

            control.removeFromSuperview()
            ShortcutFormatter.keyLabels = Fixture(character: "z")
            center.post(name: KeyboardLayout.selectionDidChangeNotification, object: nil)

            #expect(control.title == "⌥Y", "no observer is left once detached")
        }

        /// Settings pauses global interception through this forwarding; the field
        /// must report the recorder's real start and end, not just its creation.
        @Test func fieldForwardsRecordingLifetime() throws {
            let control = try recorder()
            control.performClick(nil)
            #expect(model.forwardedRecording == [true])

            try sendKey(KeyCode.escape)

            #expect(model.forwardedRecording == [true, false])
        }
    }
}
