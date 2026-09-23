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
        // SwiftUI assigns on every update; only a change is worth announcing
        didSet { if shortcut != oldValue { refreshTitle() } }
    }

    /// Why the last chord was rejected, shown next to the control by Settings.
    /// The control carries it as its accessibility help, so the error is
    /// reachable from the field itself, and announces a new one.
    var validationMessage: String? {
        didSet {
            guard validationMessage != oldValue else { return }
            refreshTitle()
            if let validationMessage {
                NSAccessibility.post(
                    element: self, notification: .announcementRequested,
                    userInfo: [.announcement: validationMessage,
                               .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        }
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

    isolated deinit {
        // A dealloc without a detach must not leak the app-wide monitor.
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        inputSourceNotificationCenter.removeObserver(self)
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

    /// Title, accessibility value and help for the current state. The title
    /// shows glyphs; the value names the chord in words, so VoiceOver reads the
    /// label ("Open WindowHop shortcut") and then the current chord, "None", or
    /// "Recording". AltTab's recorder posts the same value and title changes
    /// when recording begins and ends
    /// (`317a485b:Pods/ShortcutRecorder/Library/SRRecorderControl.m`).
    private func refreshTitle() {
        let escape = KeyCode.escape
        let delete = KeyCode.delete
        if isRecording {
            title = "Type shortcut… (\(ShortcutFormatter.keySymbol(for: escape)) cancels, "
                + "\(ShortcutFormatter.keySymbol(for: delete)) clears)"
            setAccessibilityValue("Recording")
            setAccessibilityHelp("Press a shortcut. \(ShortcutFormatter.spokenKeyName(for: escape)) "
                + "cancels, \(ShortcutFormatter.spokenKeyName(for: delete)) clears.")
        } else {
            title = shortcut?.displayString ?? "Record Shortcut…"
            setAccessibilityValue(shortcut?.spokenString ?? "None")
            setAccessibilityHelp(validationMessage)
        }
        NSAccessibility.post(element: self, notification: .valueChanged)
        NSAccessibility.post(element: self, notification: .titleChanged)
    }

    /// Where input-source changes are observed; tests substitute a private
    /// center so they never post a system-wide notification.
    var inputSourceNotificationCenter: NotificationCenter = DistributedNotificationCenter.default()

    /// The printable key's label follows the selected layout; the binding does not.
    @objc private func keyboardLayoutDidChange(_ notification: Notification) {
        refreshTitle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.willCloseNotification,
                                          NSWindow.didResignKeyNotification]
        if let oldWindow = window {
            for name in names { center.removeObserver(self, name: name, object: oldWindow) }
            inputSourceNotificationCenter.removeObserver(
                self, name: KeyboardLayout.selectionDidChangeNotification, object: nil)
        }
        if let newWindow {
            for name in names {
                center.addObserver(self, selector: #selector(recordingWindowDidEndContext(_:)),
                                   name: name, object: newWindow)
            }
            // Observed only while on screen in a window: no idle observer.
            inputSourceNotificationCenter.addObserver(
                self, selector: #selector(keyboardLayoutDidChange(_:)),
                name: KeyboardLayout.selectionDidChangeNotification, object: nil)
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
    /// The enabled macOS shortcuts, read when a chord is captured. Tests inject
    /// a fixture so they never depend on the machine's configuration.
    var systemShortcuts: @MainActor () -> [PersistentShortcut] = SystemShortcuts.enabled
    /// Asks whether to take over a macOS shortcut and reports `true` only for
    /// Use Anyway. Tests inject an answer so no modal ever runs.
    var confirmSystemShortcut: @MainActor (PersistentShortcut, NSWindow?, @escaping (Bool) -> Void) -> Void =
        ShortcutRecorderField.presentSystemShortcutAlert

    /// A warning sheet on the Settings window; Cancel is the default button and
    /// also answers Escape, so the safe choice is the easy one.
    static func presentSystemShortcutAlert(for captured: PersistentShortcut, in window: NSWindow?,
                                           completion: @escaping (Bool) -> Void) {
        let copy = captured.systemShortcutConfirmation
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Use Anyway")
        if let window {
            alert.beginSheetModal(for: window) { completion($0 == .alertSecondButtonReturn) }
        } else {
            completion(alert.runModal() == .alertSecondButtonReturn)
        }
    }

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        applyConfiguration(to: control)
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = shortcut
        control.validationMessage = validationMessage
        // SwiftUI reuses this native control across updates, so the callbacks
        // must be re-bound: otherwise they keep validating against the primary
        // shortcut and writing to the bindings that existed at creation time,
        // and a chord conflicting with the *current* primary is saved silently.
        applyConfiguration(to: control)
    }

    private func applyConfiguration(to control: ShortcutRecorderControl) {
        control.onCapture = { [weak control] captured in
            let assessment = captured.assessCapture(against: switcherShortcut, current: shortcut,
                                                    systemShortcuts: systemShortcuts())
            switch assessment {
            case .accept:
                validationMessage = nil
                shortcut = captured
            case let .reject(error):
                validationMessage = error.explanation
            case .confirmSystemShortcut:
                // Cancel keeps the previous chord and persists nothing.
                confirmSystemShortcut(captured, control?.window) { useAnyway in
                    guard useAnyway else { return }
                    validationMessage = nil
                    shortcut = captured
                }
            }
        }
        control.onClear = {
            validationMessage = nil
            shortcut = nil
        }
        control.onRecordingChanged = onRecordingChanged
    }
}
