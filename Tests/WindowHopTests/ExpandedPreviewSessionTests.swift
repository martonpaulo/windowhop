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
}
