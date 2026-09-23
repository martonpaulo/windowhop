import XCTest
@testable import WindowHopCore

/// The preview↔window assignment must be UNIQUE: two windows of the same app can
/// never receive the same snapshot (the "both WhatsApp windows showed one
/// preview" bug), a Chromium window must recognize its own snapshot even though
/// AX and the window server spell its title differently (the "Brave shows
/// another window's preview" bug), and an ambiguous window gets no preview
/// rather than a guess.
final class PreviewMatchingTests: XCTestCase {
    private typealias Request = PreviewMatcher.Request
    private typealias Candidate = PreviewMatcher.Candidate

    private static let windowFrame = CGRect(x: 0, y: 31, width: 1440, height: 869)

    func testTwoSameAppWindowsGetDistinctPreviews() {
        let requests = [
            Request(id: "a", pid: 7, title: "WhatsApp", frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
            Request(id: "b", pid: 7, title: "WhatsApp", frame: CGRect(x: 400, y: 100, width: 800, height: 600)),
        ]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "WhatsApp", frame: CGRect(x: 400, y: 100, width: 800, height: 600)),
            Candidate(index: 1, pid: 7, title: "WhatsApp", frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        let result = PreviewMatcher.assign(requests: requests, candidates: candidates)
        XCTAssertEqual(result["a"], 1)
        XCTAssertEqual(result["b"], 0)
    }

    /// Chromium reports `"Page - Brave - Profile"` through AX and `"Page"` to the
    /// window server, so equality alone matched nothing and every same-sized
    /// window fell back to window-server order — the wrong preview.
    func testChromiumWindowsWithIdenticalFramesMatchTheirOwnTitle() {
        let requests = [
            Request(id: "docs", pid: 7, title: "Docs - Brave - Personal", frame: Self.windowFrame),
            Request(id: "mail", pid: 7, title: "Mail - Brave - Personal", frame: Self.windowFrame),
            Request(id: "news", pid: 7, title: "News - Brave - Work", frame: Self.windowFrame),
        ]
        // window-server order is unrelated to the switcher's MRU order
        let candidates = [
            Candidate(index: 0, pid: 7, title: "News", frame: Self.windowFrame),
            Candidate(index: 1, pid: 7, title: "Docs", frame: Self.windowFrame),
            Candidate(index: 2, pid: 7, title: "Mail", frame: Self.windowFrame),
        ]
        let result = PreviewMatcher.assign(requests: requests, candidates: candidates)
        XCTAssertEqual(result["docs"], 1)
        XCTAssertEqual(result["mail"], 2)
        XCTAssertEqual(result["news"], 0)
    }

    func testIndistinguishableWindowsGetNoPreviewInsteadOfAGuess() {
        // same app, same frame, same title: nothing can tell them apart
        let requests = [
            Request(id: "a", pid: 7, title: "New Tab - Brave - Personal", frame: Self.windowFrame),
            Request(id: "b", pid: 7, title: "New Tab - Brave - Personal", frame: Self.windowFrame),
        ]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "New Tab", frame: Self.windowFrame),
            Candidate(index: 1, pid: 7, title: "New Tab", frame: Self.windowFrame),
        ]
        XCTAssertTrue(PreviewMatcher.assign(requests: requests, candidates: candidates).isEmpty)
    }

    func testResolvingACertainWindowUnlocksAnAmbiguousOne() {
        let requests = [
            Request(id: "unknownFrame", pid: 7, title: "Doc", frame: nil),
            Request(id: "knownFrame", pid: 7, title: "Doc", frame: Self.windowFrame),
        ]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "Doc", frame: Self.windowFrame),
            Candidate(index: 1, pid: 7, title: "Doc", frame: CGRect(x: 200, y: 200, width: 400, height: 300)),
        ]
        let result = PreviewMatcher.assign(requests: requests, candidates: candidates)
        XCTAssertEqual(result["knownFrame"], 0, "the frame match is certain")
        XCTAssertEqual(result["unknownFrame"], 1, "the only candidate left is no longer ambiguous")
    }

    func testInvisibleHelperWindowsAreNeverAssigned() {
        // Chromium keeps 1×1 and off-screen helper windows in the window list
        let requests = [Request(id: "a", pid: 7, title: "Docs", frame: nil)]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "Docs", frame: CGRect(x: 0, y: 0, width: 1, height: 1)),
        ]
        XCTAssertTrue(PreviewMatcher.assign(requests: requests, candidates: candidates).isEmpty)
    }

    func testNoCrossAppMatches() {
        let requests = [Request(id: "a", pid: 7, title: "Doc", frame: nil)]
        let candidates = [Candidate(index: 0, pid: 8, title: "Doc", frame: Self.windowFrame)]
        XCTAssertTrue(PreviewMatcher.assign(requests: requests, candidates: candidates).isEmpty)
    }

    func testTitleBreaksFrameTies() {
        let requests = [Request(id: "a", pid: 7, title: "Two", frame: Self.windowFrame)]
        let candidates = [
            Candidate(index: 0, pid: 7, title: "One", frame: Self.windowFrame),
            Candidate(index: 1, pid: 7, title: "Two", frame: Self.windowFrame),
        ]
        XCTAssertEqual(PreviewMatcher.assign(requests: requests, candidates: candidates)["a"], 1)
    }

    func testUnmatchableRequestGetsNothingRatherThanAGuess() {
        let requests = [Request(id: "a", pid: 7, title: "Alpha", frame: nil)]
        let candidates = [Candidate(index: 0, pid: 7, title: "Beta", frame: Self.windowFrame)]
        XCTAssertTrue(PreviewMatcher.assign(requests: requests, candidates: candidates).isEmpty)
    }

    /// Observed live: the window server elides the middle of a long title, so
    /// same-frame windows would all look "different" and lose their previews.
    func testElidedWindowServerTitlesStillMatchTheirWindow() {
        let requests = [
            Request(id: "repo", pid: 7,
                    title: "martonpaulo/windowhop: Switch between windows, not just apps. "
                        + "Fast, native macOS window switcher with large app icons or live "
                        + "previews — free, GPL, no telemetry. - Brave - Personal",
                    frame: Self.windowFrame),
            Request(id: "docs", pid: 7,
                    title: "Accessibility API reference for macOS applications, windows, and "
                        + "attributes | Apple Developer Documentation - Brave - Personal",
                    frame: Self.windowFrame),
        ]
        let candidates = [
            Candidate(index: 0, pid: 7,
                      title: "Accessibility API reference …le Developer Documentation",
                      frame: Self.windowFrame),
            Candidate(index: 1, pid: 7,
                      title: "martonpaulo/windowhop: Switch …ws — free, GPL, no telemetry.",
                      frame: Self.windowFrame),
        ]
        let result = PreviewMatcher.assign(requests: requests, candidates: candidates)
        XCTAssertEqual(result["repo"], 1)
        XCTAssertEqual(result["docs"], 0)
    }

    func testTitleRelations() {
        XCTAssertEqual(PreviewMatcher.titleRelation("Docs", "docs "), .equal)
        XCTAssertEqual(PreviewMatcher.titleRelation("Docs - Brave - Personal", "Docs"), .compatible)
        XCTAssertEqual(PreviewMatcher.titleRelation("Report.md — Edited", "Report.md"), .compatible)
        XCTAssertEqual(PreviewMatcher.titleRelation("Inbox", ""), .unknown)
        XCTAssertEqual(PreviewMatcher.titleRelation("Inbox", "Drafts"), .different)
        XCTAssertEqual(PreviewMatcher.titleRelation("Inbox Rules", "Inbox"), .different,
                       "a shared word is not a decoration")
        XCTAssertEqual(PreviewMatcher.titleRelation("Quarterly planning notes for the team",
                                                    "Quarterly pl…for the team"), .compatible)
        XCTAssertEqual(PreviewMatcher.titleRelation("Quarterly planning notes for the team",
                                                    "Q…m"), .different,
                       "too little of the title survived to mean anything")
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
