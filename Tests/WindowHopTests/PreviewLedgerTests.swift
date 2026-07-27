import XCTest
@testable import WindowHopCore

/// Captures finish asynchronously and out of order; the ledger decides what a
/// late result may still do. These are the regression rules that keep a
/// preview from ever reaching the wrong window or a vanished one.
final class PreviewLedgerTests: XCTestCase {
    func testLateResultAfterEvictionIsDiscarded() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a", "b"])
        ledger.evict("a")
        XCTAssertFalse(ledger.shouldStore("a"))
        XCTAssertFalse(ledger.shouldDeliver("a", capturedIn: generation))
        XCTAssertTrue(ledger.shouldStore("b"))
        XCTAssertTrue(ledger.shouldDeliver("b", capturedIn: generation))
    }

    func testStaleSessionResultStoresButNeverDeliversLive() {
        var ledger = PreviewLedger<String>()
        let first = ledger.beginSession(ids: ["a"])
        let second = ledger.beginSession(ids: ["a"])
        // the old session's capture is still fresh content for the cache,
        // but only the current session may paint tiles
        XCTAssertTrue(ledger.shouldStore("a"))
        XCTAssertFalse(ledger.shouldDeliver("a", capturedIn: first))
        XCTAssertTrue(ledger.shouldDeliver("a", capturedIn: second))
    }

    func testEndSessionStopsDeliveryButKeepsCacheWarm() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.endSession()
        XCTAssertTrue(ledger.shouldStore("a"))
        XCTAssertFalse(ledger.shouldDeliver("a", capturedIn: generation))
    }

    func testRapidReopenDeliversOnlyToTheCurrentSession() {
        var ledger = PreviewLedger<String>()
        let first = ledger.beginSession(ids: ["a"])
        ledger.endSession()
        let third = ledger.beginSession(ids: ["a"])
        XCTAssertFalse(ledger.shouldDeliver("a", capturedIn: first))
        XCTAssertTrue(ledger.shouldDeliver("a", capturedIn: third))
    }

    func testExtendingASessionDeliversToTheNewWindow() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.extendSession(ids: ["b"])
        XCTAssertTrue(ledger.shouldDeliver("b", capturedIn: generation))
    }

    func testExtendingASessionKeepsInFlightCapturesDeliverable() {
        // a window appearing mid-session must not blank the tiles that are still
        // filling in: extending may never invalidate the running generation
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.extendSession(ids: ["b"])
        XCTAssertTrue(ledger.shouldDeliver("a", capturedIn: generation))
    }

    func testExtendedWindowLosesDeliveryOnceTheSessionEnds() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a"])
        ledger.extendSession(ids: ["b"])
        ledger.endSession()
        XCTAssertTrue(ledger.shouldStore("b"))
        XCTAssertFalse(ledger.shouldDeliver("b", capturedIn: generation))
    }

    func testEvictAllDiscardsEveryInFlightResult() {
        var ledger = PreviewLedger<String>()
        let generation = ledger.beginSession(ids: ["a", "b"])
        ledger.evictAll()
        XCTAssertFalse(ledger.shouldStore("a"))
        XCTAssertFalse(ledger.shouldDeliver("b", capturedIn: generation))
    }
}
