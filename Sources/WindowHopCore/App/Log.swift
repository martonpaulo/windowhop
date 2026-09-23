import Foundation
import os

/// Diagnostics through the unified log, one `Logger` per area. Read them with
/// `log stream --level debug --predicate 'subsystem == "<id>"'`, where `<id>` is the bundle
/// identifier, or `WindowHop` for the unbundled `swift build` binary.
///
/// Privacy: the unified log redacts dynamic values unless they are marked. Messages here
/// log counts, phases, commands, display placement and frames, so those values are
/// `privacy: .public`. A window title, app name, path or any other user content must be
/// `privacy: .private`.
///
/// `os` stays out of `Core/`, which remains Foundation-only (#100).
enum Log {
    /// The bundle identifier, read at runtime; the process name only for the unbundled
    /// development binary, so no literal identifier lives in code.
    static let subsystem = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName

    static let input = Logger(subsystem: subsystem, category: "input")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let windows = Logger(windowsLog)
    static let previews = Logger(subsystem: subsystem, category: "previews")
    static let updates = Logger(subsystem: subsystem, category: "updates")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")

    /// Kept for `isWindowsDebugEnabled`: `Logger` cannot report whether a level is enabled.
    private static let windowsLog = OSLog(subsystem: subsystem, category: "windows")

    /// Guards a debug trace whose inputs are expensive to compute, not only to format.
    static var isWindowsDebugEnabled: Bool { windowsLog.isEnabled(type: .debug) }
}
