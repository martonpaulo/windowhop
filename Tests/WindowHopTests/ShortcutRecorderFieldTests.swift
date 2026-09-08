import AppKit
import SwiftUI
import XCTest
@testable import WindowHopCore

/// SwiftUI keeps one native recorder alive across updates, so its validation
/// must follow the currently selected switcher shortcut rather than the one
/// that existed when the control was created.
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

    private var model: Model!
    private var hosting: NSHostingView<Host>!

    override func setUp() {
        super.setUp()
        model = Model()
        hosting = NSHostingView(rootView: Host(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
        flushUpdates()
    }

    override func tearDown() {
        hosting = nil
        model = nil
        super.tearDown()
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
