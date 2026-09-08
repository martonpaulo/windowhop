import XCTest
@testable import WindowHopCore

/// Expanded capture must never start after its session, target or request has
/// been superseded. These drive the real ordering rule with a controlled
/// lookup, so cancellation can land exactly while the lookup is pending.
final class ExpandedCaptureFlowTests: XCTestCase {
    /// Counts what the flow actually spent, per stage.
    private actor Recorder {
        private(set) var captures = 0
        func recordCapture() { captures += 1 }
    }

    private struct Candidate {}

    /// Main-thread test state, so the flow's main-actor stages can read and
    /// mutate it without concurrent captures of local variables.
    @MainActor
    private final class State {
        var isCurrentRemaining = Int.max
        var deliveries = 0

        /// Reports current until it has answered `isCurrentRemaining` times.
        func isCurrent() -> Bool {
            defer { isCurrentRemaining -= 1 }
            return isCurrentRemaining > 0
        }
    }

    /// A lookup the test can hold open until it decides to release it.
    private final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func open() { semaphore.signal() }
        func wait() { semaphore.wait() }
    }

    private func run(isCurrent: @escaping @MainActor @Sendable () -> Bool,
                     lookup: @escaping () async -> Candidate? = { Candidate() },
                     capture: @escaping (Candidate) async -> String? = { _ in "image" },
                     recorder: Recorder,
                     delivered: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async -> ExpandedCaptureFlow.Outcome {
        await ExpandedCaptureFlow.run(
            lookup: lookup,
            isCurrent: isCurrent,
            capture: { candidate in
                await recorder.recordCapture()
                return await capture(candidate)
            },
            deliver: delivered)
    }

    func testCancellationDuringLookupStartsNoCapture() async {
        let recorder = Recorder()
        let gate = Gate()
        let state = await State()

        async let outcome = run(
            isCurrent: { state.isCurrent() },
            lookup: { gate.wait(); return Candidate() },
            recorder: recorder,
            delivered: { _ in state.deliveries += 1 })

        // the session ends while shareable-content lookup is still pending
        await MainActor.run { state.isCurrentRemaining = 0 }
        gate.open()

        let result = await outcome
        let captures = await recorder.captures
        let deliveries = await state.deliveries
        XCTAssertEqual(result, .cancelledBeforeCapture)
        XCTAssertEqual(captures, 0, "no screenshot may start after cancellation")
        XCTAssertEqual(deliveries, 0)
    }

    func testCurrentRequestCapturesOnceAndDelivers() async {
        let recorder = Recorder()
        let state = await State()

        let result = await run(isCurrent: { true }, recorder: recorder,
                               delivered: { _ in state.deliveries += 1 })

        let captures = await recorder.captures
        let deliveries = await state.deliveries
        XCTAssertEqual(result, .delivered)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(deliveries, 1)
    }

    func testCancellationAfterCaptureDiscardsTheResult() async {
        let recorder = Recorder()
        let state = await State()
        await MainActor.run { state.isCurrentRemaining = 1 }

        // current before the capture, obsolete once it has finished
        let result = await run(isCurrent: { state.isCurrent() }, recorder: recorder,
                               delivered: { _ in state.deliveries += 1 })

        let captures = await recorder.captures
        let deliveries = await state.deliveries
        XCTAssertEqual(result, .cancelledAfterCapture)
        XCTAssertEqual(captures, 1, "work already started is allowed to finish")
        XCTAssertEqual(deliveries, 0, "an obsolete result must not be delivered")
    }

    func testUnmatchedWindowStartsNoCapture() async {
        let recorder = Recorder()

        let result = await run(isCurrent: { true }, lookup: { nil }, recorder: recorder)

        let captures = await recorder.captures
        XCTAssertEqual(result, .noCandidate)
        XCTAssertEqual(captures, 0)
    }

    func testFailedCaptureDeliversNothing() async {
        let recorder = Recorder()
        let state = await State()

        let result = await run(isCurrent: { true }, capture: { _ in nil }, recorder: recorder,
                               delivered: { _ in state.deliveries += 1 })

        let deliveries = await state.deliveries
        XCTAssertEqual(result, .captureFailed)
        XCTAssertEqual(deliveries, 0)
    }
}
