import Foundation
import Testing

@testable import WindowHopKit

struct ExpandedPreviewSessionTests {
    @Test func settledTargetBecomesExpandedWithoutCommitOrOriginState() throws {
        var session = ExpandedPreviewSession<String>()
        let requestOrNil = session.begin(targetedWindowID: "target")
        let request = try #require(requestOrNil)

        #expect(session.settle(request, availableWindowIDs: ["target"]) == "target")
        #expect(session.expandedWindowID == "target")
    }

    @Test func closedTargetCannotExpandAndNeighborCanReplaceIt() throws {
        var session = ExpandedPreviewSession<String>()
        let closedRequestOrNil = session.begin(targetedWindowID: "closed")
        let closedRequest = try #require(closedRequestOrNil)
        session.retainAvailable(["neighbor"])

        #expect(session.settle(closedRequest, availableWindowIDs: ["neighbor"]) == nil)
        let neighborRequestOrNil = session.target("neighbor")
        let neighborRequest = try #require(neighborRequestOrNil)
        #expect(
            session.settle(
                neighborRequest,
                availableWindowIDs: ["neighbor"]) == "neighbor")
    }

    @Test func rapidNavigationExpandsOnlyLatestSettledTarget() throws {
        var session = ExpandedPreviewSession<String>()
        let firstOrNil = session.begin(targetedWindowID: "one")
        let first = try #require(firstOrNil)
        let secondOrNil = session.target("two")
        let second = try #require(secondOrNil)
        let thirdOrNil = session.target("three")
        let third = try #require(thirdOrNil)
        let available: Set<String> = ["one", "two", "three"]

        #expect(session.settle(first, availableWindowIDs: available) == nil)
        #expect(session.settle(second, availableWindowIDs: available) == nil)
        #expect(session.settle(third, availableWindowIDs: available) == "three")
    }

    @Test func sameApplicationWindowsRemainDistinctByStableIdentity() throws {
        struct WindowID: Hashable {
            let application: String
            let stableID: Int
        }
        let first = WindowID(application: "Browser", stableID: 1)
        let second = WindowID(application: "Browser", stableID: 2)
        var session = ExpandedPreviewSession<WindowID>()

        let requestOrNil = session.begin(targetedWindowID: second)
        let request = try #require(requestOrNil)
        #expect(session.settle(request, availableWindowIDs: [first, second]) == second)
    }

    @Test func resetInvalidatesExpiredRequest() throws {
        var session = ExpandedPreviewSession<String>()
        let requestOrNil = session.begin(targetedWindowID: "target")
        let request = try #require(requestOrNil)
        session.reset()

        #expect(session.settle(request, availableWindowIDs: ["target"]) == nil)
        #expect(session.targetedWindowID == nil)
        #expect(session.expandedWindowID == nil)
    }

    // MARK: - Idempotent re-targeting (issue #21)

    /// A store refresh that preserves the selection re-targets the same window.
    /// The pending request must survive: no new request, no new generation.
    @Test func retargetingTheSameWindowBeforeSettleKeepsThePendingRequest() throws {
        var session = ExpandedPreviewSession<String>()
        let pending = session.begin(targetedWindowID: "A")

        #expect(session.target("A") == nil, "an unchanged target creates no new request")
        #expect(
            session.settle(try #require(pending), availableWindowIDs: ["A"]) == "A",
            "the original request must still settle")
    }

    @Test func retargetingTheSameWindowAfterSettleKeepsItExpanded() throws {
        var session = ExpandedPreviewSession<String>()
        let request = session.begin(targetedWindowID: "A")
        _ = session.settle(try #require(request), availableWindowIDs: ["A"])

        #expect(session.target("A") == nil)
        #expect(session.expandedWindowID == "A")
    }

    @Test func changingTheTargetStillInvalidatesTheOldRequest() throws {
        var session = ExpandedPreviewSession<String>()
        let stale = session.begin(targetedWindowID: "A")

        let fresh = session.target("B")

        #expect(fresh?.windowID == "B")
        #expect(
            session.settle(try #require(stale), availableWindowIDs: ["A", "B"]) == nil,
            "the superseded request must not settle")
    }

    /// Navigating away and back is a real change in both directions, so it
    /// restarts dwell rather than reusing the abandoned request.
    @Test func navigatingAwayAndBackRestartsDwell() throws {
        var session = ExpandedPreviewSession<String>()
        let first = session.begin(targetedWindowID: "A")
        _ = session.target("B")

        let again = session.target("A")

        #expect(again?.windowID == "A")
        #expect(again != first)
        #expect(session.settle(try #require(first), availableWindowIDs: ["A", "B"]) == nil)
        #expect(session.settle(try #require(again), availableWindowIDs: ["A", "B"]) == "A")
    }
}
