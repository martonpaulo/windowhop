import ApplicationServices
import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// A Space-change re-enumeration may fail. A failed read must keep each window where
/// it was last seen; only a successful read, even an empty one, may move it.
final class SpaceMembershipTests: XCTestCase {
    private let tracked = ["a", "b", "c"]

    func testTimeoutPreservesLastKnownLocation() {
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: WindowEnumeration<String>.unavailable)
        XCTAssertTrue(result.currentSpace.isEmpty, "no flag may change on a failed read")
        XCTAssertTrue(result.suspects.isEmpty, "a busy app's windows are not dead")
    }

    func testInvalidApplicationPreservesFlagsAndSuspectsEveryWindow() {
        let result = SpaceMembership.reconcile(tracked: tracked,
                                               enumeration: WindowEnumeration<String>.applicationInvalid)
        XCTAssertTrue(result.currentSpace.isEmpty)
        XCTAssertEqual(result.suspects, tracked)
    }

    func testEmptySuccessMarksWindowsOffSpace() {
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed([]))
        XCTAssertEqual(result.currentSpace, ["a": false, "b": false, "c": false])
        XCTAssertEqual(result.suspects, tracked)
    }

    func testNormalSuccessSetsFlagsAndSuspectsTheAbsent() {
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed(["a", "c", "new"]))
        XCTAssertEqual(result.currentSpace, ["a": true, "b": false, "c": true],
                       "untracked listed windows are discovered elsewhere, not flagged here")
        XCTAssertEqual(result.suspects, ["b"])
    }

    func testLaterSuccessConvergesAfterTimeout() {
        var flags = ["a": true, "b": true, "c": false]
        for enumeration: WindowEnumeration<String> in [.unavailable, .listed(["c"])] {
            let result = SpaceMembership.reconcile(tracked: tracked, enumeration: enumeration)
            flags.merge(result.currentSpace) { _, new in new }
        }
        XCTAssertEqual(flags, ["a": false, "b": false, "c": true])
    }

    // MARK: - AX result mapping

    func testAXReadOutcomesMapToDistinctEnumerations() {
        let window = AXUIElementCreateApplication(getpid())
        let windows = [window, window] as CFArray

        XCTAssertEqual(AXUIElement.windowEnumeration(result: .success, value: windows).listedWindows, [window],
                       "a normal success lists the windows, deduplicated")
        XCTAssertEqual(AXUIElement.windowEnumeration(result: .noValue, value: nil), .listed([]),
                       "an app with no windows is an empty success")
        XCTAssertEqual(AXUIElement.windowEnumeration(result: .cannotComplete, value: nil), .unavailable,
                       "a timeout is not an empty inventory")
        XCTAssertEqual(AXUIElement.windowEnumeration(result: .failure, value: nil), .unavailable)
        XCTAssertEqual(AXUIElement.windowEnumeration(result: .invalidUIElement, value: nil), .applicationInvalid,
                       "a dead app element is reported as such")
    }
}
