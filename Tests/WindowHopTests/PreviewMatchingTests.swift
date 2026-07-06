import XCTest
@testable import WindowHopCore

/// The preview↔window assignment must be UNIQUE: two windows of the same app can
/// never receive the same snapshot (the "both WhatsApp windows showed one
/// preview" bug), and an unmatchable window gets no preview rather than a guess.
final class PreviewMatchingTests: XCTestCase {
    private typealias Request = PreviewProvider.MatchRequest
    private typealias Candidate = PreviewProvider.MatchCandidate

    func testTwoSameAppWindowsGetDistinctPreviews() {
        let requests = [
            Request(id: "a", pid: 7, title: "WhatsApp", frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
            Request(id: "b", pid: 7, title: "WhatsApp", frame: CGRect(x: 400, y: 100, width: 800, height: 600)),
        ]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "WhatsApp", frame: CGRect(x: 400, y: 100, width: 800, height: 600)),
            Candidate(index: 1, pid: 7, title: "WhatsApp", frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        let result = PreviewProvider.assign(requests: requests, candidates: candidates)
        XCTAssertEqual(result["a"], 1)
        XCTAssertEqual(result["b"], 0)
    }

    func testEqualTitlesWithUnknownFramesNeverShareACandidate() {
        // frames unavailable: title matching must still consume candidates uniquely
        let requests = [
            Request(id: "a", pid: 7, title: "WhatsApp", frame: nil),
            Request(id: "b", pid: 7, title: "WhatsApp", frame: nil),
            Request(id: "c", pid: 7, title: "WhatsApp", frame: nil),
        ]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "WhatsApp", frame: .zero),
            Candidate(index: 1, pid: 7, title: "WhatsApp", frame: .zero),
        ]
        let result = PreviewProvider.assign(requests: requests, candidates: candidates)
        let assigned = result.values.sorted()
        XCTAssertEqual(Set(assigned).count, assigned.count, "no candidate may be assigned twice")
        XCTAssertEqual(assigned.count, 2, "the third request stays unmatched (icon fallback)")
    }

    func testNoCrossAppMatches() {
        let requests = [Request(id: "a", pid: 7, title: "Doc", frame: nil)]
        let candidates = [Candidate(index: 0, pid: 8, title: "Doc", frame: .zero)]
        XCTAssertTrue(PreviewProvider.assign(requests: requests, candidates: candidates).isEmpty)
    }

    func testFramePreferredOverTitleAndTitleBreaksFrameTies() {
        let frame = CGRect(x: 10, y: 10, width: 500, height: 400)
        let requests = [Request(id: "a", pid: 7, title: "Two", frame: frame)]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "One", frame: frame),
            Candidate(index: 1, pid: 7, title: "Two", frame: frame),
        ]
        XCTAssertEqual(PreviewProvider.assign(requests: requests, candidates: candidates)["a"], 1)
    }

    func testUnmatchableRequestGetsNothingRatherThanAGuess() {
        let requests = [Request(id: "a", pid: 7, title: "Alpha", frame: nil)]
        let candidates = [Candidate(index: 0, pid: 7, title: "Beta", frame: .zero)]
        XCTAssertTrue(PreviewProvider.assign(requests: requests, candidates: candidates).isEmpty)
    }
}

/// Multi-row grid navigation: ↑/↓ move by one row, clamped; ←/→ stay linear.
final class GridNavigationTests: XCTestCase {
    func testVerticalArrowsMoveByRow() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 8) // selection 1
        state.updateColumns(3)
        XCTAssertEqual(state.arrow(.down), .select(index: 4))
        XCTAssertEqual(state.arrow(.down), .select(index: 7))
        XCTAssertEqual(state.arrow(.up), .select(index: 4))
        XCTAssertEqual(state.arrow(.left), .select(index: 3))
    }

    func testVerticalArrowsClampAtGridEdges() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 8) // selection 1
        state.updateColumns(3)
        XCTAssertEqual(state.arrow(.up), .none, "no wrap above the first row")
        _ = state.arrow(.down) // 4
        _ = state.arrow(.down) // 7
        XCTAssertEqual(state.arrow(.down), .none, "no wrap below the last row")
    }

    func testSingleRowKeepsWrappingBehavior() {
        var state = SwitcherState()
        _ = state.trigger(backward: false, itemCount: 3) // selection 1
        state.updateColumns(1)
        XCTAssertEqual(state.arrow(.down), .select(index: 2))
        XCTAssertEqual(state.arrow(.down), .select(index: 0), "single row wraps like before")
    }
}
