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
    }

    private struct Host: View {
        @ObservedObject var model: Model

        var body: some View {
            ShortcutRecorderField(shortcut: $model.shortcut,
                                  validationMessage: $model.validationMessage,
                                  switcherShortcut: model.switcherShortcut)
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

    /// Escape stops recording without reaching either callback.
    func testCancellationPersistsNothing() throws {
        let control = try recorder()
        control.performClick(nil)

        control.shortcut = nil
        XCTAssertNil(model.shortcut)
        XCTAssertNil(model.validationMessage)
    }
}
