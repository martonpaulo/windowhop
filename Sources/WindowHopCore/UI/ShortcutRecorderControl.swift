import AppKit
import SwiftUI

/// A native shortcut recorder built on NSButton + a local key monitor — no
/// third-party library. Click to record; press a chord to assign; Escape
/// cancels; Delete clears. Validation runs before anything is saved and
/// conflicts are reported inline through the binding.
///
/// Recording is bound to the recorder's own window: it ends when that window
/// closes or resigns key, and when the control leaves it. The Settings window
/// is retained (`isReleasedWhenClosed = false`), so closing it never detaches
/// the control; without the window observers the app-wide monitor would stay
/// armed and swallow the next key event. AltTab's recorder ends recording on
/// the same resign-key notification
/// (`317a485b:Pods/ShortcutRecorder/Library/SRRecorderControl.m`, `viewWillMoveToWindow:`).
final class ShortcutRecorderControl: NSButton {
    var onCapture: ((PersistentShortcut) -> Void)?
    var onClear: (() -> Void)?
    /// Fires `true` when recording starts and `false` exactly once when it ends,
    /// whatever ended it (capture, Escape, Delete, click, close, resign, detach).
    var onRecordingChanged: ((Bool) -> Void)?

    private var keyMonitor: Any?
    /// Whether the app-wide key monitor is installed; true only while recording.
    var isInterceptingKeys: Bool { keyMonitor != nil }
    private var isRecording = false {
        didSet { refreshTitle() }
    }

    var shortcut: PersistentShortcut? {
        didSet { refreshTitle() }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        setAccessibilityLabel("Open WindowHop shortcut")
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        // A dealloc without a detach must not leak the app-wide monitor.
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    @objc private func toggleRecording() {
        isRecording ? endRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording, window != nil else { return }
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleRecordingKeyDown(event)
        }
        onRecordingChanged?(true)
    }

    /// The monitor's body. Returns `nil` to consume a key event taken by the
    /// recorder, or the event unchanged when it belongs to another window or
    /// recording is over.
    func handleRecordingKeyDown(_ event: NSEvent) -> NSEvent? {
        guard isRecording, let window, event.window === window else { return event }
        let keyCode = Int64(event.keyCode)
        if keyCode == KeyCode.escape {
            endRecording()
            return nil
        }
        if keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete {
            endRecording()
            onClear?()
            return nil
        }
        let flags = CGEventFlags(nsFlags: event.modifierFlags)
        endRecording()
        onCapture?(PersistentShortcut(keyCode: keyCode, modifiers: flags))
        return nil
    }

    /// The single, idempotent end of a recording.
    private func endRecording() {
        guard isRecording else { return }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isRecording = false
        onRecordingChanged?(false)
    }

    @objc private func recordingWindowDidEndContext(_ notification: Notification) {
        endRecording()
    }

    private func refreshTitle() {
        if isRecording {
            title = "Type shortcut… (⎋ cancels, ⌫ clears)"
        } else if let shortcut {
            title = shortcut.displayString
        } else {
            title = "Record Shortcut…"
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.willCloseNotification,
                                          NSWindow.didResignKeyNotification]
        if let oldWindow = window {
            for name in names { center.removeObserver(self, name: name, object: oldWindow) }
        }
        if let newWindow {
            for name in names {
                center.addObserver(self, selector: #selector(recordingWindowDidEndContext(_:)),
                                   name: name, object: newWindow)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Detaching covers switching Settings panes: the toolbar tab view
        // controller removes unselected pane views.
        if window == nil {
            endRecording()
        }
    }
}

extension CGEventFlags {
    init(nsFlags: NSEvent.ModifierFlags) {
        var flags = CGEventFlags()
        if nsFlags.contains(.command) { flags.insert(.maskCommand) }
        if nsFlags.contains(.option) { flags.insert(.maskAlternate) }
        if nsFlags.contains(.control) { flags.insert(.maskControl) }
        if nsFlags.contains(.shift) { flags.insert(.maskShift) }
        self = flags
    }
}

/// SwiftUI wrapper used by the Settings form.
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: PersistentShortcut?
    @Binding var validationMessage: String?
    let switcherShortcut: ShortcutSpec
    /// Forwarded from the recorder: `true` when recording starts, `false` once
    /// when it ends. Settings uses it to pause global interception meanwhile.
    var onRecordingChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        applyConfiguration(to: control)
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = shortcut
        // SwiftUI reuses this native control across updates, so the callbacks
        // must be re-bound: otherwise they keep validating against the primary
        // shortcut and writing to the bindings that existed at creation time,
        // and a chord conflicting with the *current* primary is saved silently.
        applyConfiguration(to: control)
    }

    private func applyConfiguration(to control: ShortcutRecorderControl) {
        control.onCapture = { captured in
            if let error = captured.validate(against: switcherShortcut) {
                validationMessage = error.explanation
            } else {
                validationMessage = nil
                shortcut = captured
            }
        }
        control.onClear = {
            validationMessage = nil
            shortcut = nil
        }
        control.onRecordingChanged = onRecordingChanged
    }
}
