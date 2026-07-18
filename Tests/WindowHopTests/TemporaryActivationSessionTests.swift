import XCTest
@testable import WindowHopCore

final class TemporaryActivationSessionTests: XCTestCase {
    func testConfirmCommitsTargetWithoutRestoringOrigin() {
        var session = TemporaryActivationSession<String>()
        let request = session.begin(originWindowID: "origin", targetedWindowID: "target")!

        XCTAssertEqual(session.settle(request, availableWindowIDs: ["origin", "target"]), "target")
        XCTAssertEqual(session.commit("target", availableWindowIDs: ["origin", "target"]), "target")
        XCTAssertEqual(session.committedWindowID, "target")
    }

    func testCancelRestoresExactOrigin() {
        var session = TemporaryActivationSession<String>()
        let request = session.begin(originWindowID: "origin", targetedWindowID: "target")!
        _ = session.settle(request, availableWindowIDs: ["origin", "target"])

        XCTAssertEqual(session.cancel(availableWindowIDs: ["origin", "target"]), "origin")
        XCTAssertNil(session.committedWindowID)
    }

    func testCancelFallsBackSafelyWhenOriginClosed() {
        var session = TemporaryActivationSession<String>()
        _ = session.begin(originWindowID: "origin", targetedWindowID: "target")
        session.retainAvailable(["target"])

        XCTAssertNil(session.cancel(availableWindowIDs: ["target"]))
    }

    func testClosedTargetCannotActivateAndNeighborCanReplaceIt() {
        var session = TemporaryActivationSession<String>()
        let closedRequest = session.begin(originWindowID: "origin", targetedWindowID: "closed")!
        session.retainAvailable(["origin", "neighbor"])

        XCTAssertNil(session.settle(closedRequest, availableWindowIDs: ["origin", "neighbor"]))
        let neighborRequest = session.target("neighbor")!
        XCTAssertEqual(session.settle(neighborRequest,
                                      availableWindowIDs: ["origin", "neighbor"]), "neighbor")
    }

    func testRapidNavigationActivatesOnlyLatestSettledTarget() {
        var session = TemporaryActivationSession<String>()
        let first = session.begin(originWindowID: "origin", targetedWindowID: "one")!
        let second = session.target("two")!
        let third = session.target("three")!
        let available: Set<String> = ["origin", "one", "two", "three"]

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
        var session = TemporaryActivationSession<WindowID>()

        let request = session.begin(originWindowID: first, targetedWindowID: second)!
        XCTAssertEqual(session.settle(request, availableWindowIDs: [first, second]), second)
        XCTAssertEqual(session.cancel(availableWindowIDs: [first, second]), first)
    }
}
