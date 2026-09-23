import ApplicationServices
import Foundation
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

/// A Space-change re-enumeration may fail. A failed read must keep each window where
/// it was last seen; only a successful read, even an empty one, may move it.
struct SpaceMembershipTests {
    private let tracked = ["a", "b", "c"]

    @Test func timeoutPreservesLastKnownLocation() {
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: WindowEnumeration<String>.unavailable)
        #expect(result.currentSpace.isEmpty, "no flag may change on a failed read")
        #expect(result.suspects.isEmpty, "a busy app's windows are not dead")
    }

    @Test func invalidApplicationPreservesFlagsAndSuspectsEveryWindow() {
        let result = SpaceMembership.reconcile(
            tracked: tracked,
            enumeration: WindowEnumeration<String>.applicationInvalid)
        #expect(result.currentSpace.isEmpty)
        #expect(result.suspects == tracked)
    }

    @Test func emptySuccessMarksWindowsOffSpace() {
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed([]))
        #expect(result.currentSpace == ["a": false, "b": false, "c": false])
        #expect(result.suspects == tracked)
    }

    @Test func normalSuccessSetsFlagsAndSuspectsTheAbsent() {
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed(["a", "c", "new"]))
        #expect(
            result.currentSpace == ["a": true, "b": false, "c": true],
            "untracked listed windows are discovered elsewhere, not flagged here")
        #expect(result.suspects == ["b"])
    }

    @Test func laterSuccessConvergesAfterTimeout() {
        var flags = ["a": true, "b": true, "c": false]
        for enumeration: WindowEnumeration<String> in [.unavailable, .listed(["c"])] {
            let result = SpaceMembership.reconcile(tracked: tracked, enumeration: enumeration)
            flags.merge(result.currentSpace) { _, new in new }
        }
        #expect(flags == ["a": false, "b": false, "c": true])
    }

    // MARK: - AX result mapping

    @Test func axReadOutcomesMapToDistinctEnumerations() {
        let window = AXUIElementCreateApplication(getpid())
        let windows = [window, window] as CFArray

        #expect(
            AXUIElement.windowEnumeration(result: .success, value: windows).listedWindows == [window],
            "a normal success lists the windows, deduplicated")
        #expect(
            AXUIElement.windowEnumeration(result: .noValue, value: nil) == .listed([]),
            "an app with no windows is an empty success")
        #expect(
            AXUIElement.windowEnumeration(result: .cannotComplete, value: nil) == .unavailable,
            "a timeout is not an empty inventory")
        #expect(AXUIElement.windowEnumeration(result: .failure, value: nil) == .unavailable)
        #expect(
            AXUIElement.windowEnumeration(result: .invalidUIElement, value: nil) == .applicationInvalid,
            "a dead app element is reported as such")
    }
}
