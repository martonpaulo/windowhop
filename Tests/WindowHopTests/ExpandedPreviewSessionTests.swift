import XCTest
@testable import WindowHopCore

final class ExpandedPreviewSessionTests: XCTestCase {
    func testSettledTargetBecomesExpandedWithoutCommitOrOriginState() {
        var session = ExpandedPreviewSession<String>()
        let request = session.begin(targetedWindowID: "target")!

        XCTAssertEqual(session.settle(request, availableWindowIDs: ["target"]), "target")
        XCTAssertEqual(session.expandedWindowID, "target")
    }

    func testClosedTargetCannotExpandAndNeighborCanReplaceIt() {
        var session = ExpandedPreviewSession<String>()
        let closedRequest = session.begin(targetedWindowID: "closed")!
        session.retainAvailable(["neighbor"])

        XCTAssertNil(session.settle(closedRequest, availableWindowIDs: ["neighbor"]))
        let neighborRequest = session.target("neighbor")!
        XCTAssertEqual(session.settle(neighborRequest,
                                      availableWindowIDs: ["neighbor"]), "neighbor")
    }

    func testRapidNavigationExpandsOnlyLatestSettledTarget() {
        var session = ExpandedPreviewSession<String>()
        let first = session.begin(targetedWindowID: "one")!
        let second = session.target("two")!
        let third = session.target("three")!
        let available: Set<String> = ["one", "two", "three"]

        XCTAssertNil(session.settle(first, availableWindowIDs: available))
        XCTAssertNil(session.settle(second, availableWindowIDs: available))
        XCTAssertEqual(session.settle(third, availableWindowIDs: available), "three")
    }

    func testSameApplicationWindowsRemainDistinctByStableIdentity() {
        struct WindowID: Hashable {
            let application: String
            let stableID: Int
        }
        let first = WindowID(application: "Browser", stableID: 1)
        let second = WindowID(application: "Browser", stableID: 2)
        var session = ExpandedPreviewSession<WindowID>()

        let request = session.begin(targetedWindowID: second)!
        XCTAssertEqual(session.settle(request, availableWindowIDs: [first, second]), second)
    }

    func testResetInvalidatesExpiredRequest() {
        var session = ExpandedPreviewSession<String>()
        let request = session.begin(targetedWindowID: "target")!
        session.reset()

        XCTAssertNil(session.settle(request, availableWindowIDs: ["target"]))
        XCTAssertNil(session.targetedWindowID)
        XCTAssertNil(session.expandedWindowID)
    }

    // MARK: - Idempotent re-targeting (issue #21)

    /// A store refresh that preserves the selection re-targets the same window.
    /// The pending request must survive: no new request, no new generation.
    func testRetargetingTheSameWindowBeforeSettleKeepsThePendingRequest() {
        var session = ExpandedPreviewSession<String>()
        let pending = session.begin(targetedWindowID: "A")

        XCTAssertNil(session.target("A"), "an unchanged target creates no new request")
        XCTAssertEqual(session.settle(try! XCTUnwrap(pending), availableWindowIDs: ["A"]), "A",
                       "the original request must still settle")
    }

    func testRetargetingTheSameWindowAfterSettleKeepsItExpanded() {
        var session = ExpandedPreviewSession<String>()
        let request = session.begin(targetedWindowID: "A")
        _ = session.settle(try! XCTUnwrap(request), availableWindowIDs: ["A"])

        XCTAssertNil(session.target("A"))
        XCTAssertEqual(session.expandedWindowID, "A")
    }

    func testChangingTheTargetStillInvalidatesTheOldRequest() {
        var session = ExpandedPreviewSession<String>()
        let stale = session.begin(targetedWindowID: "A")

        let fresh = session.target("B")

        XCTAssertEqual(fresh?.windowID, "B")
        XCTAssertNil(session.settle(try! XCTUnwrap(stale), availableWindowIDs: ["A", "B"]),
                     "the superseded request must not settle")
    }

    /// Navigating away and back is a real change in both directions, so it
    /// restarts dwell rather than reusing the abandoned request.
    func testNavigatingAwayAndBackRestartsDwell() {
        var session = ExpandedPreviewSession<String>()
        let first = session.begin(targetedWindowID: "A")
        _ = session.target("B")

        let again = session.target("A")

        XCTAssertEqual(again?.windowID, "A")
        XCTAssertNotEqual(again, first)
        XCTAssertNil(session.settle(try! XCTUnwrap(first), availableWindowIDs: ["A", "B"]))
        XCTAssertEqual(session.settle(try! XCTUnwrap(again), availableWindowIDs: ["A", "B"]), "A")
    }
}
