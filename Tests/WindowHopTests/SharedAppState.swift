import AppKit
import Testing

/// The suites that drive AppKit and process-wide state: windows and key status,
/// the main run loop, `UserDefaults.standard`, the default notification center and
/// `ShortcutFormatter.keyLabels`. XCTest ran every test one at a time; Swift
/// Testing runs suites in parallel, so main-actor tests of different suites could
/// interleave between one test's setup, body and teardown, or at any suspension.
/// Nested here, these suites run one test at a time, setup to teardown.
@Suite(.serialized)
enum SharedAppState {}

extension Trait where Self == ConditionTrait {
    /// Skips a test that opens a panel on a real screen when the runner has none.
    static var needsDisplay: Self {
        .enabled("needs a display") { await MainActor.run { !NSScreen.screens.isEmpty } }
    }
}
