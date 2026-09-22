import AppKit
import SwiftUI
import XCTest
@testable import WindowHopCore

/// SwiftUI keeps one native recorder alive across updates, so its validation
/// must follow the currently selected switcher shortcut rather than the one
/// that existed when the control was created. Recording itself is bound to the
/// recorder's window: it must end on close, resign-key and detach.
@MainActor
final class ShortcutRecorderFieldTests: XCTestCase {
    /// Isolated test state: these tests never touch `Preferences.shared`.
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
            ShortcutRecorderField(shortcut: $model.shortcut,
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

    override func setUp() {
        super.setUp()
        model = Model()
        hosting = NSHostingView(rootView: Host(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
        // Retained like the Settings window, so closing it never detaches the
        // recorder by itself. Never ordered on screen.
        window = makeRetainedWindow(frame: hosting.frame)
        window.contentView = hosting
        flushUpdates()
    }

    override func tearDown() {
        window.close()
        window = nil
        hosting = nil
        model = nil
        super.tearDown()
    }

    private func makeRetainedWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable],
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
        return try XCTUnwrap(search(hosting), "the recorder control is not in the hierarchy")
    }

    private func chord(_ modifiers: CGEventFlags) -> PersistentShortcut {
        PersistentShortcut(keyCode: KeyCode.tab, modifiers: modifiers)
    }

    private func keyEvent(_ keyCode: Int64, _ modifiers: NSEvent.ModifierFlags = [],
                          for target: NSWindow? = nil) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: (target ?? window).windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(keyCode)))
    }

    /// Delivers a real key-down through `NSApplication.sendEvent(_:)`, the
    /// dispatch path the recorder's local monitor observes.
    private func sendKey(_ keyCode: Int64, _ modifiers: NSEvent.ModifierFlags = [],
                         to target: NSWindow? = nil) throws {
        NSApplication.shared.sendEvent(try keyEvent(keyCode, modifiers, for: target))
    }

    /// Starts recording and collects every transition of the recording state.
    private func startRecording(_ control: ShortcutRecorderControl) -> Transitions {
        let transitions = Transitions()
        control.onRecordingChanged = { transitions.values.append($0) }
        control.performClick(nil)
        XCTAssertTrue(control.isInterceptingKeys, "recording installs the key monitor")
        return transitions
    }

    /// Once recording ended, no monitor is left and a key for the recorder's
    /// window reaches neither callback.
    private func assertNoLongerCapturing(_ control: ShortcutRecorderControl,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) throws {
        var callbacks = 0
        control.onCapture = { _ in callbacks += 1 }
        control.onClear = { callbacks += 1 }

        try sendKey(Self.keyJ, [.control, .option])
        try sendKey(KeyCode.delete)

        XCTAssertFalse(control.isInterceptingKeys, "no key monitor survives", file: file, line: line)
        XCTAssertEqual(callbacks, 0, "no capture callback survives", file: file, line: line)
        XCTAssertEqual(control.title, "Record Shortcut…", "the idle title is back",
                       file: file, line: line)
    }

    /// Positive control: a key sent through AppKit's dispatch reaches the
    /// recorder's monitor in the test process.
    func testSentChordIsCapturedAndEndsRecording() throws {
        let control = try recorder()
        let transitions = startRecording(control)

        try sendKey(Self.keyK, [.control, .option])

        XCTAssertEqual(model.shortcut,
                       PersistentShortcut(keyCode: Self.keyK, modifiers: [.maskControl, .maskAlternate]))
        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(transitions.values, [true, false])
        XCTAssertFalse(control.isInterceptingKeys)
    }

    func testClosingRetainedWindowEndsRecording() throws {
        let control = try recorder()
        let transitions = startRecording(control)

        window.close()

        XCTAssertNotNil(control.window, "a retained window keeps the control attached")
        XCTAssertEqual(transitions.values, [true, false])
        try assertNoLongerCapturing(control)
        XCTAssertNil(model.shortcut)
    }

    func testResignKeyEndsRecording() throws {
        let control = try recorder()
        let transitions = startRecording(control)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        XCTAssertEqual(transitions.values, [true, false])
        try assertNoLongerCapturing(control)
        XCTAssertNil(model.shortcut)
    }

    func testAnotherWindowResigningKeyDoesNotEndRecording() throws {
        let control = try recorder()
        let other = makeRetainedWindow(frame: .zero)
        defer { other.close() }
        let transitions = startRecording(control)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)

        XCTAssertEqual(transitions.values, [true])
        XCTAssertTrue(control.isInterceptingKeys)
    }

    func testKeyEventsForOtherWindowsAreNotCaptured() throws {
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

        XCTAssertIdentical(control.handleRecordingKeyDown(foreign), foreign,
                           "another window's key event is passed on unchanged")
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(transitions.values, [true], "recording continues in its own window")
        XCTAssertNil(model.shortcut)
    }

    func testDetachEndsRecordingOnce() throws {
        let control = try recorder()
        let transitions = startRecording(control)

        hosting.removeFromSuperview()

        XCTAssertNil(control.window)
        XCTAssertFalse(control.isInterceptingKeys)
        XCTAssertEqual(transitions.values, [true, false])
        window.close()
        XCTAssertEqual(transitions.values, [true, false], "a later close does not end it twice")
    }

    func testCaptureEndsRecordingExactlyOnce() throws {
        let control = try recorder()
        let transitions = startRecording(control)

        try sendKey(Self.keyK, [.control, .option])
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        window.close()

        XCTAssertEqual(transitions.values, [true, false])
    }

    func testCaptureAfterPrimaryChangeRejectsTheNewPrimaryChord() throws {
        let control = try recorder()
        model.switcherShortcut = .optionTab
        flushUpdates()
        XCTAssertIdentical(try recorder(), control, "SwiftUI must reuse the native control")

        control.onCapture?(chord(.maskAlternate))

        XCTAssertNil(model.shortcut, "a conflicting chord must not be persisted")
        XCTAssertEqual(model.validationMessage,
                       PersistentShortcut.ValidationError.conflictsWithSwitcherShortcut.explanation)
    }

    func testChordConflictingOnlyWithTheFormerPrimaryIsAccepted() throws {
        let control = try recorder()
        model.switcherShortcut = .optionTab
        flushUpdates()

        control.onCapture?(chord(.maskCommand))

        XCTAssertEqual(model.shortcut, chord(.maskCommand))
        XCTAssertNil(model.validationMessage)
    }

    func testValidCaptureClearsAnEarlierValidationMessage() throws {
        let control = try recorder()
        control.onCapture?(chord(.maskCommand))
        XCTAssertNotNil(model.validationMessage)

        control.onCapture?(chord([.maskControl, .maskShift]))

        XCTAssertEqual(model.shortcut, chord([.maskControl, .maskShift]))
        XCTAssertNil(model.validationMessage)
    }

    func testClearResetsShortcutAndMessageThroughCurrentBindings() throws {
        let control = try recorder()
        control.onCapture?(chord(.maskControl))
        model.switcherShortcut = .optionTab
        flushUpdates()

        control.onClear?()

        XCTAssertNil(model.shortcut)
        XCTAssertNil(model.validationMessage)
    }

    /// A real Escape through the recorder's monitor ends recording without
    /// reaching either callback; the next chord is no longer captured.
    func testEscapeCancelsRecordingWithoutSaving() throws {
        let installed = PersistentShortcut(keyCode: Self.keyK, modifiers: [.maskControl, .maskAlternate])
        model.shortcut = installed
        flushUpdates()
        let control = try recorder()
        let transitions = startRecording(control)
        var callbacks = 0
        let bindingCapture = control.onCapture
        let bindingClear = control.onClear
        control.onCapture = { callbacks += 1; bindingCapture?($0) }
        control.onClear = { callbacks += 1; bindingClear?() }

        try sendKey(KeyCode.escape)

        XCTAssertEqual(callbacks, 0, "Escape reaches neither capture nor clear")
        XCTAssertEqual(model.shortcut, installed, "the installed shortcut is kept")
        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(transitions.values, [true, false])
        XCTAssertFalse(control.isInterceptingKeys, "no key monitor survives the cancellation")
        XCTAssertEqual(control.title, installed.displayString)

        try sendKey(Self.keyJ, [.control, .option])
        let later = try keyEvent(Self.keyJ, [.control, .option])

        XCTAssertIdentical(control.handleRecordingKeyDown(later), later,
                           "a later chord is passed on, not swallowed")
        XCTAssertEqual(callbacks, 0, "a later chord is not captured")
        XCTAssertEqual(model.shortcut, installed)
        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(transitions.values, [true, false])
    }

    // MARK: - Conflicts with macOS and standard app commands (#56)

    private static let commandSpace = PersistentShortcut(keyCode: KeyCode.space, modifiers: [.maskCommand])
    private static let controlOptionK = PersistentShortcut(keyCode: keyK, modifiers: [.maskControl, .maskAlternate])

    func testStandardAppCommandIsRejectedWithItsName() throws {
        model.shortcut = Self.controlOptionK
        flushUpdates()
        let control = try recorder()

        control.onCapture?(PersistentShortcut(keyCode: 12 /* Q */, modifiers: [.maskCommand]))

        XCTAssertEqual(model.shortcut, Self.controlOptionK, "nothing is persisted")
        XCTAssertEqual(model.validationMessage,
                       "⌘Q is the Quit command in apps. Choose a combination that isn't a standard app command.")
        XCTAssertEqual(model.confirmationRequests, [])
    }

    func testSystemShortcutCancelKeepsThePreviousChord() throws {
        model.shortcut = Self.controlOptionK
        model.systemShortcuts = [Self.commandSpace]
        model.confirmationAnswer = false
        flushUpdates()
        let control = try recorder()

        control.onCapture?(Self.commandSpace)

        XCTAssertEqual(model.confirmationRequests, [Self.commandSpace])
        XCTAssertEqual(model.shortcut, Self.controlOptionK, "Cancel persists nothing")
        XCTAssertNil(model.validationMessage)
    }

    func testSystemShortcutUseAnywayPersists() throws {
        model.systemShortcuts = [Self.commandSpace]
        model.confirmationAnswer = true
        model.validationMessage = "an earlier rejection"
        flushUpdates()
        let control = try recorder()

        control.onCapture?(Self.commandSpace)

        XCTAssertEqual(model.confirmationRequests, [Self.commandSpace])
        XCTAssertEqual(model.shortcut, Self.commandSpace)
        XCTAssertNil(model.validationMessage)
    }

    func testReRecordingTheStoredSystemChordNeedsNoConfirmation() throws {
        model.shortcut = Self.commandSpace
        model.systemShortcuts = [Self.commandSpace]
        flushUpdates()
        let control = try recorder()

        control.onCapture?(Self.commandSpace)

        XCTAssertEqual(model.confirmationRequests, [])
        XCTAssertEqual(model.shortcut, Self.commandSpace)
    }

    /// Selecting another input source relabels the recorded key while the
    /// recorder is in a window, and never changes the binding. A private center
    /// stands in for the distributed one, so no system-wide notification is posted.
    func testInputSourceChangeRefreshesTheLabelOnlyWhileInAWindow() {
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
        XCTAssertEqual(control.title, "⌥Z")

        ShortcutFormatter.keyLabels = Fixture(character: "y")
        center.post(name: KeyboardLayout.selectionDidChangeNotification, object: nil)

        XCTAssertEqual(control.title, "⌥Y")
        XCTAssertEqual(control.accessibilityValue() as? String, "Option Y")
        XCTAssertEqual(control.shortcut, recorded, "the binding is unchanged")

        control.removeFromSuperview()
        ShortcutFormatter.keyLabels = Fixture(character: "z")
        center.post(name: KeyboardLayout.selectionDidChangeNotification, object: nil)

        XCTAssertEqual(control.title, "⌥Y", "no observer is left once detached")
    }

    /// Settings pauses global interception through this forwarding; the field
    /// must report the recorder's real start and end, not just its creation.
    func testFieldForwardsRecordingLifetime() throws {
        let control = try recorder()
        control.performClick(nil)
        XCTAssertEqual(model.forwardedRecording, [true])

        try sendKey(KeyCode.escape)

        XCTAssertEqual(model.forwardedRecording, [true, false])
    }
}
