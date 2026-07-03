import AppKit
import WindowHopCore

if !DebugHarness.runIfRequested(CommandLine.arguments) {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
