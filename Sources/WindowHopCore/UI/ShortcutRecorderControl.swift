import AppKit
import SwiftUI

/// A native shortcut recorder built on NSButton + a local key monitor — no
/// third-party library. Click to record; press a chord to assign; Escape
/// cancels; Delete clears. Validation runs before anything is saved and
/// conflicts are reported inline through the binding.
final class ShortcutRecorderControl: NSButton {
    var onCapture: ((PersistentShortcut) -> Void)?
    var onClear: (() -> Void)?

    private var keyMonitor: Any?
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

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let keyCode = Int64(event.keyCode)
            if keyCode == KeyCode.escape {
                self.stopRecording()
                return nil
            }
            if keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete {
                self.stopRecording()
                self.onClear?()
                return nil
            }
            let flags = CGEventFlags(nsFlags: event.modifierFlags)
            self.stopRecording()
            self.onCapture?(PersistentShortcut(keyCode: keyCode, modifiers: flags))
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isRecording = false
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRecording()
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

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
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
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = shortcut
    }
}
