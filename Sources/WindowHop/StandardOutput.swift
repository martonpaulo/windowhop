import Foundation

/// Writes one line to standard output, unbuffered. The CLI harnesses (`--dump-windows`,
/// `--dump-previews`, `--updater-e2e`, the demo `READY` handshake) produce stdout as their
/// result, so this is their output channel; diagnostics go to the unified log (`Log`).
func writeLine(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}
