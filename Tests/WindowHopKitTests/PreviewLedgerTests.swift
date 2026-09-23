import Foundation
import Testing

@testable import WindowHopKit

/// Captures finish asynchronously and out of order; the ledger decides what a
/// late result may still do. These are the regression rules that keep a
/// preview from ever reaching the wrong window or a vanished one.
struct PreviewLedgerTests {
    @Test func lateResultAfterEvictionIsDiscarded() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a", "b"])
        ledger.evict("a")
        #expect(!ledger.shouldStore("a"))
        #expect(!ledger.shouldDeliver("a", capturedIn: generation))
        #expect(ledger.shouldStore("b"))
        #expect(ledger.shouldDeliver("b", capturedIn: generation))
    }

    @Test func staleSessionResultStoresButNeverDeliversLive() {
        var ledger = PreviewLedger<String>()
        let first = ledger.beginSession(ids: ["a"])
        let second = ledger.beginSession(ids: ["a"])
        // the old session's capture is still fresh content for the cache,
        // but only the current session may paint tiles
        #expect(ledger.shouldStore("a"))
        #expect(!ledger.shouldDeliver("a", capturedIn: first))
        #expect(ledger.shouldDeliver("a", capturedIn: second))
    }

    @Test func endSessionStopsDeliveryButKeepsCacheWarm() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.endSession()
        #expect(ledger.shouldStore("a"))
        #expect(!ledger.shouldDeliver("a", capturedIn: generation))
    }

    @Test func rapidReopenDeliversOnlyToTheCurrentSession() {
        var ledger = PreviewLedger<String>()
        let first = ledger.beginSession(ids: ["a"])
        ledger.endSession()
        let third = ledger.beginSession(ids: ["a"])
        #expect(!ledger.shouldDeliver("a", capturedIn: first))
        #expect(ledger.shouldDeliver("a", capturedIn: third))
    }

    @Test func extendingASessionDeliversToTheNewWindow() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.extendSession(ids: ["b"])
        #expect(ledger.shouldDeliver("b", capturedIn: generation))
    }

    @Test func extendingASessionKeepsInFlightCapturesDeliverable() {
        // a window appearing mid-session must not blank the tiles that are still
        // filling in: extending may never invalidate the running generation
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.extendSession(ids: ["b"])
        #expect(ledger.shouldDeliver("a", capturedIn: generation))
    }

    @Test func extendedWindowLosesDeliveryOnceTheSessionEnds() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.extendSession(ids: ["b"])
        ledger.endSession()
        #expect(ledger.shouldStore("b"))
        #expect(!ledger.shouldDeliver("b", capturedIn: generation))
    }

    @Test func evictAllDiscardsEveryInFlightResult() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a", "b"])
        ledger.evictAll()
        #expect(!ledger.shouldStore("a"))
        #expect(!ledger.shouldDeliver("b", capturedIn: generation))
    }

    // MARK: - Retry allowance (#91)

    @Test func aFailedCaptureGetsOneRetryPerSession() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a", "b"])
        #expect(ledger.claimRetry("a", capturedIn: generation) == true)
        #expect(ledger.claimRetry("a", capturedIn: generation) == false, "a second retry")
        #expect(ledger.claimRetry("b", capturedIn: generation) == true, "allowances are per window")
    }

    @Test func aNewSessionRestoresTheRetryAllowance() {
        var ledger = PreviewLedger<String>()
        let first = ledger.beginSession(ids: ["a"])
        #expect(ledger.claimRetry("a", capturedIn: first) == true)
        ledger.endSession()
        let second = ledger.beginSession(ids: ["a"])
        #expect(ledger.claimRetry("a", capturedIn: second) == true)
    }

    @Test func noRetryAfterEviction() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.evict("a")
        #expect(ledger.claimRetry("a", capturedIn: generation) == false)
    }

    @Test func noRetryForAnEndedOrReplacedSession() {
        var ledger = PreviewLedger<String>()
        let first = ledger.beginSession(ids: ["a"])
        ledger.endSession()
        #expect(ledger.claimRetry("a", capturedIn: first) == false)
        let second = ledger.beginSession(ids: ["a"])
        #expect(ledger.claimRetry("a", capturedIn: first) == false, "a superseded session")
        #expect(ledger.claimRetry("a", capturedIn: second) == true)
    }

    @Test func aWindowThatJoinedTheSessionGetsItsOwnRetry() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        #expect(ledger.claimRetry("late", capturedIn: generation) == false, "not in the session yet")
        ledger.extendSession(ids: ["late"])
        #expect(ledger.claimRetry("late", capturedIn: generation) == true)
    }
}
