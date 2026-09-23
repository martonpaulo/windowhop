import Foundation
import Testing

@testable import WindowHopKit

/// A tile capture that fails for a reason that can pass on its own gets one
/// delayed retry in its session (#91); every other failure is final at once.
/// These drive the real flow with deterministic fakes: no screen, no
/// permission, no real delay.
@MainActor
struct TileCaptureFlowTests {
    private struct Candidate { let id: String }

    /// Records every stage the flow spends and what it reports.
    @MainActor
    private final class Harness {
        var lookups = 0
        var captures: [String: Int] = [:]
        var delivered: [String] = []
        var unavailable: [[String]] = []
        var sleeps: [Duration] = []
        var events: [String] = []
        var current = true
        var ledger = PreviewLedger<String>()
        var generation = 0
        let budget: CaptureBudget

        /// Answers for each lookup, in order; the last one repeats.
        var lookupResults: [Set<String>?] = []
        /// Answers for each capture of an id, in order; the last one repeats.
        var captureResults: [String: [TileCaptureResult<String>]] = [:]
        var onSleep: () -> Void = {}
        var maxInFlight = 0

        init(ids: [String], limit: Int = 4) {
            budget = CaptureBudget(limit: limit)
            generation = ledger.beginSession(ids: ids)
            budget.advance(to: generation)
        }

        func run(_ ids: [String]) async {
            await TileCaptureFlow.run(
                ids: ids,
                budget: budget,
                generation: generation,
                lookup: { (requested: [String]) -> [String: Candidate]? in
                    self.lookups += 1
                    self.events.append("lookup")
                    let index = min(self.lookups - 1, max(self.lookupResults.count - 1, 0))
                    let matchable =
                        self.lookupResults.isEmpty
                        ? Set(requested) : self.lookupResults[index]
                    guard let matchable else { return nil }
                    var matched: [String: Candidate] = [:]
                    for id in requested where matchable.contains(id) {
                        matched[id] = Candidate(id: id)
                    }
                    return matched
                },
                capture: { (candidate: Candidate) -> TileCaptureResult<String> in
                    let attempt = self.captures[candidate.id, default: 0]
                    self.captures[candidate.id] = attempt + 1
                    self.events.append("capture \(candidate.id)")
                    self.maxInFlight = max(self.maxInFlight, self.budget.inFlight)
                    await Task.yield()
                    let results: [TileCaptureResult<String>] =
                        self.captureResults[candidate.id] ?? [.captured("image")]
                    return results[min(attempt, results.count - 1)]
                },
                isCurrent: { self.current },
                claimRetries: { ids in
                    ids.filter { self.ledger.claimRetry($0, capturedIn: self.generation) }
                },
                sleep: { duration in
                    self.sleeps.append(duration)
                    self.events.append("sleep")
                    self.onSleep()
                },
                deliver: { (id: String, _: String) in self.delivered.append(id) },
                unavailable: { ids in
                    self.unavailable.append(ids)
                    self.events.append("unavailable \(ids.joined(separator: ","))")
                })
        }
    }

    private static let transient = TileCaptureResult<String>.failed(.captureFailed(transient: true))

    @Test func aTransientFailureThenSuccessDeliversWithTwoAttempts() async {
        let harness = Harness(ids: ["a"])
        harness.captureResults["a"] = [Self.transient, .captured("image")]

        await harness.run(["a"])

        #expect(harness.captures["a"] == 2)
        #expect(harness.delivered == ["a"])
        #expect(harness.unavailable.isEmpty)
        #expect(harness.sleeps == [PreviewRetryPolicy.delay])
    }

    @Test func anExhaustedRetryMakesTwoAttemptsAndOneUnavailable() async {
        let harness = Harness(ids: ["a"])
        harness.captureResults["a"] = [Self.transient]

        await harness.run(["a"])

        #expect(harness.captures["a"] == 2, "one retry, never a loop")
        #expect(harness.unavailable == [["a"]])
        #expect(harness.delivered.isEmpty)
    }

    @Test func stableFailuresAreFinalAfterOneAttempt() async {
        let stable: [PreviewFailure] = [
            .invalidTarget, .permissionDenied,
            .captureFailed(transient: false),
        ]
        for failure in stable {
            let harness = Harness(ids: ["a"])
            harness.captureResults["a"] = [.failed(failure)]

            await harness.run(["a"])

            #expect(harness.captures["a"] == 1, "\(failure)")
            #expect(harness.lookups == 1, "\(failure)")
            #expect(harness.unavailable == [["a"]], "\(failure)")
            #expect(harness.sleeps.isEmpty, "\(failure)")
        }
    }

    /// An ambiguous or missing match never retries and never picks a window.
    @Test func noMatchIsFinalAndCapturesNothing() async {
        let harness = Harness(ids: ["a", "b"])
        harness.lookupResults = [["b"]]

        await harness.run(["a", "b"])

        #expect(harness.lookups == 1)
        #expect(harness.captures["a"] == nil)
        #expect(harness.unavailable == [["a"]])
        #expect(harness.delivered == ["b"])
        #expect(harness.sleeps.isEmpty)
    }

    /// A failed shared inventory read is retried once for the whole batch,
    /// not once per tile.
    @Test func aLookupFailureForManyIDsMakesExactlyTwoLookups() async {
        let ids = ["a", "b", "c", "d", "e"]
        let harness = Harness(ids: ids)
        harness.lookupResults = [nil]

        await harness.run(ids)

        #expect(harness.lookups == 2)
        #expect(harness.captures.isEmpty)
        #expect(harness.unavailable == [ids])
    }

    @Test func aLookupFailureThenSuccessCapturesEveryTile() async {
        let ids = ["a", "b", "c"]
        let harness = Harness(ids: ids)
        harness.lookupResults = [nil, Set(ids)]

        await harness.run(ids)

        #expect(harness.lookups == 2)
        #expect(Set(harness.delivered) == Set(ids))
        #expect(harness.unavailable.isEmpty)
    }

    /// The session ended, was replaced, left Window Previews or lost the grant
    /// while the retry waited: no second lookup, capture or delivery.
    @Test func aSessionThatStopsDuringTheDelaySpendsNothingMore() async {
        let harness = Harness(ids: ["a"])
        harness.captureResults["a"] = [Self.transient, .captured("image")]
        harness.onSleep = { harness.current = false }

        await harness.run(["a"])

        #expect(harness.lookups == 1)
        #expect(harness.captures["a"] == 1)
        #expect(harness.delivered.isEmpty)
        #expect(harness.unavailable.isEmpty, "a stopped session reports nothing")
    }

    @Test func anEvictedWindowGetsNoRetry() async {
        let harness = Harness(ids: ["a", "b"])
        harness.captureResults["a"] = [Self.transient, .captured("image")]
        harness.captureResults["b"] = [Self.transient, .captured("image")]
        harness.onSleep = { harness.ledger.evict("a") }

        await harness.run(["a", "b"])

        #expect(harness.captures["a"] == 1)
        #expect(harness.captures["b"] == 2)
        #expect(harness.delivered == ["b"])
        #expect(harness.unavailable == [["a"]])
    }

    /// The allowance is per session: a later batch in the same session (a
    /// window that joined) cannot retry the same window again.
    @Test func theRetryAllowanceIsUsedOnlyOncePerSession() async {
        let harness = Harness(ids: ["a"])
        harness.captureResults["a"] = [Self.transient]

        await harness.run(["a"])
        await harness.run(["a"])

        #expect(harness.captures["a"] == 3, "two attempts, then one without a retry")
        #expect(harness.unavailable == [["a"], ["a"]])
    }

    /// Stable failures are shown at once; only retryable tiles wait.
    @Test func stableFailuresAreReportedBeforeTheRetryDelay() async {
        let harness = Harness(ids: ["a", "b"])
        harness.captureResults["a"] = [.failed(.invalidTarget)]
        harness.captureResults["b"] = [Self.transient, .captured("image")]

        await harness.run(["a", "b"])

        let unavailableIndex = harness.events.firstIndex(of: "unavailable a")
        let sleepIndex = harness.events.firstIndex(of: "sleep")
        #expect(unavailableIndex != nil)
        #expect(sleepIndex != nil)
        if let unavailableIndex, let sleepIndex {
            #expect(unavailableIndex < sleepIndex)
        }
        #expect(harness.delivered == ["b"])
    }

    @Test func capturesStayWithinTheSharedBudget() async {
        let ids = (0..<9).map { "w\($0)" }
        let harness = Harness(ids: ids, limit: 4)

        await harness.run(ids)

        #expect(Set(harness.delivered) == Set(ids))
        #expect(harness.maxInFlight <= 4)
        #expect(harness.budget.inFlight == 0, "every slot is given back")
    }

    /// A replaced session refuses the budget: captures that have not started
    /// never start, and nothing is reported for them.
    @Test func aSupersededBudgetGenerationStartsNoCapture() async {
        let harness = Harness(ids: ["a"])
        harness.budget.advance(to: harness.generation + 1)

        await harness.run(["a"])

        #expect(harness.captures.isEmpty)
        #expect(harness.unavailable.isEmpty)
        #expect(harness.sleeps.isEmpty)
    }

    @Test func retryPolicyClassification() {
        #expect(PreviewRetryPolicy.isRetryable(.lookupFailed))
        #expect(PreviewRetryPolicy.isRetryable(.captureFailed(transient: true)))
        #expect(!PreviewRetryPolicy.isRetryable(.captureFailed(transient: false)))
        #expect(!PreviewRetryPolicy.isRetryable(.noMatch))
        #expect(!PreviewRetryPolicy.isRetryable(.invalidTarget))
        #expect(!PreviewRetryPolicy.isRetryable(.permissionDenied))
    }
}
