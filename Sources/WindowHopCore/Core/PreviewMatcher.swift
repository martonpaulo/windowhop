import CoreGraphics
import Foundation

/// Pairs the windows WindowHop knows through Accessibility (requests) with the
/// window-server windows a snapshot can be taken from (candidates).
///
/// The two sides describe the same windows with different data:
///
/// - Titles disagree by design. Chromium apps report `"Page – Brave – Profile"`
///   through AX while the window server only knows `"Page"`, so equality alone
///   silently fails for every Brave/Chrome window and used to leave the frame as
///   the only signal.
/// - Frames agree exactly, but they are *not* unique: same-size, stacked,
///   zoomed, or full-screen windows of one app share a frame, and an app also
///   owns invisible helper windows.
///
/// So neither signal decides alone. Every plausible pair is scored, and a pair
/// is only accepted when it is the unambiguous best choice for BOTH sides: the
/// candidate is this request's clear winner *and* the request is that
/// candidate's clear winner. Anything ambiguous stays unassigned — the tile then
/// keeps its placeholder, because a preview of the wrong window is worse than no
/// preview.
enum PreviewMatcher {
    struct Request {
        let id: AnyHashable
        let pid: pid_t
        let title: String
        let frame: CGRect?
    }

    struct Candidate {
        /// Position in the caller's candidate list; returned as the assignment.
        let index: Int
        let pid: pid_t
        let title: String
        let frame: CGRect
    }

    /// Per-edge frame agreement between an AX frame and a window-server frame.
    /// They are normally identical; the tolerance only absorbs rounding and a
    /// window that settled between the two reads.
    private static let frameTolerance: CGFloat = 5
    /// Two candidates whose scores differ by less than this are a tie.
    private static let ambiguityMargin: CGFloat = 0.5

    /// How two titles for the same window can relate once decoration differs.
    enum TitleRelation {
        case equal
        /// One title is the other plus an app/profile/state decoration
        /// (`"Page – Brave – Personal"` vs `"Page"`).
        case compatible
        /// At least one side has no title to compare (helper windows).
        case unknown
        case different
    }

    /// Lower is better: primary tier first, frame distance as the tiebreaker.
    private struct Score: Comparable {
        let tier: Int
        let distance: CGFloat

        static func < (lhs: Score, rhs: Score) -> Bool {
            lhs.tier == rhs.tier ? lhs.distance < rhs.distance : lhs.tier < rhs.tier
        }

        /// A tie means "indistinguishable", which is what makes a pair unusable.
        func isTied(with other: Score) -> Bool {
            tier == other.tier && abs(distance - other.distance) < ambiguityMargin
        }
    }

    /// Unique assignment of candidates to requests. Every candidate is consumed
    /// at most once, so two windows of the same app can never share a preview,
    /// and requests without a clear match are simply absent from the result.
    static func assign(requests: [Request], candidates: [Candidate]) -> [AnyHashable: Int] {
        var assigned: [AnyHashable: Int] = [:]
        var openRequests = Set(requests.indices)
        // helper windows too small to capture are not real candidates
        var openCandidates = Set(candidates.indices.filter {
            candidates[$0].frame.width > 1 && candidates[$0].frame.height > 1
        })
        // Resolving the certain pairs frees candidates, which can turn a
        // previously ambiguous request into a certain one; repeat until settled.
        while !openRequests.isEmpty, !openCandidates.isEmpty {
            var round: [(request: Int, candidate: Int)] = []
            for requestIndex in openRequests.sorted() {
                guard let candidateIndex = clearWinner(
                        among: openCandidates,
                        scoredBy: { score(requests[requestIndex], candidates[$0]) }),
                      clearWinner(among: openRequests,
                                  scoredBy: { score(requests[$0], candidates[candidateIndex]) })
                        == requestIndex else { continue }
                round.append((requestIndex, candidateIndex))
            }
            if round.isEmpty { break }
            for pair in round {
                assigned[requests[pair.request].id] = candidates[pair.candidate].index
                openRequests.remove(pair.request)
                openCandidates.remove(pair.candidate)
            }
        }
        return assigned
    }

    /// The single best element, or nil when nothing scores or the best two are
    /// indistinguishable.
    private static func clearWinner(among indices: Set<Int>,
                                    scoredBy score: (Int) -> Score?) -> Int? {
        // sorted by index first, so equal scores always resolve the same way
        let scored = indices.sorted().compactMap { index in score(index).map { (index, $0) } }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        let runnerUp = scored.filter { $0.0 != best.0 }.min(by: { $0.1 < $1.1 })
        if let runnerUp, best.1.isTied(with: runnerUp.1) { return nil }
        return best.0
    }

    /// Nil when the pair is impossible (different apps, or neither the frame nor
    /// the title supports it).
    private static func score(_ request: Request, _ candidate: Candidate) -> Score? {
        guard request.pid == candidate.pid else { return nil }
        let distance = request.frame.map { frameDistance($0, candidate.frame) }
        let framesAgree = request.frame.map { framesMatch($0, candidate.frame) } ?? false
        let relation = titleRelation(request.title, candidate.title)
        let tier: Int
        switch (framesAgree, relation) {
        case (true, .equal): tier = 0
        case (true, .compatible): tier = 1
        case (true, .unknown): tier = 2
        case (false, .equal): tier = 3
        case (false, .compatible): tier = 4
        // same frame but a conflicting title: the title changed between the two
        // reads (a tab switched, a document was edited) — still the same window
        case (true, .different): tier = 5
        case (false, .unknown), (false, .different): return nil
        }
        return Score(tier: tier, distance: distance ?? 0)
    }

    private static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < frameTolerance
            && abs(a.origin.y - b.origin.y) < frameTolerance
            && abs(a.width - b.width) < frameTolerance
            && abs(a.height - b.height) < frameTolerance
    }

    private static func frameDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.origin.x - b.origin.x) + abs(a.origin.y - b.origin.y)
            + abs(a.width - b.width) + abs(a.height - b.height)
    }

    /// Separators apps use between the window title and whatever they append to
    /// it (app name, profile, state).
    private static let titleSeparators = [" - ", " – ", " — ", " | ", " · "]

    static func titleRelation(_ lhs: String, _ rhs: String) -> TitleRelation {
        let left = normalized(lhs)
        let right = normalized(rhs)
        if left.isEmpty || right.isEmpty { return .unknown }
        if left == right { return .equal }
        if isDecorated(left, of: right) || isDecorated(right, of: left) { return .compatible }
        return .different
    }

    private static func normalized(_ title: String) -> String {
        title.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// True when `decorated` is `core` with a separated addition on either end.
    private static func isDecorated(_ decorated: String, of core: String) -> Bool {
        titleSeparators.contains {
            decorated.hasPrefix(core + $0) || decorated.hasSuffix($0 + core)
        }
    }
}
