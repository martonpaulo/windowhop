import Foundation
import Testing

@testable import WindowHopKit

/// Preview captures from every path share one ceiling. These drive the real
/// budget with held slots, so the ceiling, refill order and cancellation are
/// observed without touching the screen (#86).
@MainActor
struct CaptureBudgetTests {
    /// Records which workers got a slot, in order, and which were refused.
    private actor Log {
        private(set) var started: [Int] = []
        private(set) var refused: [Int] = []
        func start(_ id: Int) { started.append(id) }
        func refuse(_ id: Int) { refused.append(id) }
    }

    /// Polls until `condition` holds; waiters park asynchronously, so the
    /// test waits for the budget to reach the state it is about to assert.
    private func eventually(
        _ condition: @escaping () async -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<2000 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("condition not reached", sourceLocation: sourceLocation)
    }

    /// Starts one worker per id; each keeps its slot until the test releases it.
    private func startWorkers(
        _ ids: Range<Int>, budget: CaptureBudget, generation: Int,
        log: Log
    ) -> [Task<Void, Never>] {
        ids.map { id in
            Task {
                if await budget.acquire(generation: generation) {
                    await log.start(id)
                } else {
                    await log.refuse(id)
                }
            }
        }
    }

    @Test func noMoreThanTheLimitHoldASlotAcrossCallers() async {
        let budget = CaptureBudget(limit: 4)
        let log = Log()
        budget.advance(to: 1)
        // an initial batch and two newcomer batches of the same session
        _ = startWorkers(0..<4, budget: budget, generation: 1, log: log)
        _ = startWorkers(4..<7, budget: budget, generation: 1, log: log)
        _ = startWorkers(7..<10, budget: budget, generation: 1, log: log)

        await eventually { await log.started.count == 4 }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let started = await log.started.count
        #expect(started == 4)
        #expect(budget.inFlight == 4)
        budget.advance(to: 2)
    }

    @Test func aFinishedCaptureHandsItsSlotToTheOldestWaiter() async {
        let budget = CaptureBudget(limit: 1)
        let log = Log()
        budget.advance(to: 1)
        _ = startWorkers(0..<1, budget: budget, generation: 1, log: log)
        await eventually { await log.started == [0] }
        for id in 1...3 {
            _ = startWorkers(id..<id + 1, budget: budget, generation: 1, log: log)
            // let each waiter park before the next one arrives
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        budget.release()
        await eventually { await log.started == [0, 1] }
        budget.release()
        await eventually { await log.started == [0, 1, 2] }

        #expect(budget.inFlight == 1, "a handed-over slot is still one slot")
        budget.advance(to: 2)
    }

    @Test func theDwellSnapshotIsServedBeforeQueuedTiles() async {
        let budget = CaptureBudget(limit: 1)
        let log = Log()
        budget.advance(to: 1)
        _ = startWorkers(0..<1, budget: budget, generation: 1, log: log)
        await eventually { await log.started == [0] }
        _ = startWorkers(1..<3, budget: budget, generation: 1, log: log)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let dwell = Task {
            if await budget.acquire(generation: 1, jumpingQueue: true) { await log.start(99) }
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        budget.release()
        await dwell.value

        let started = await log.started
        #expect(started == [0, 99])
        budget.advance(to: 2)
    }

    @Test func anEndedSessionRefusesWaitersButLetsRunningCapturesFinish() async {
        let budget = CaptureBudget(limit: 2)
        let log = Log()
        budget.advance(to: 1)
        _ = startWorkers(0..<5, budget: budget, generation: 1, log: log)
        await eventually { await log.started.count == 2 }
        try? await Task.sleep(nanoseconds: 20_000_000)

        budget.advance(to: 2)

        await eventually { await log.refused.count == 3 }
        #expect(budget.inFlight == 2, "running captures keep their slots")
        budget.release()
        budget.release()
        #expect(budget.inFlight == 0)
        let started = await log.started.count
        #expect(started == 2, "no waiter of the ended session started")
    }

    @Test func aStaleRequestNeverTakesASlot() async {
        let budget = CaptureBudget(limit: 4)
        budget.advance(to: 3)

        let granted = await budget.acquire(generation: 2)

        #expect(!granted)
        #expect(budget.inFlight == 0)
    }

    @Test func theNextSessionUsesSlotsFreedByTheLastOne() async {
        let budget = CaptureBudget(limit: 1)
        budget.advance(to: 1)
        let first = await budget.acquire(generation: 1)
        #expect(first)

        // a capture of the ended session is still running when the next opens
        budget.advance(to: 2)
        let log = Log()
        _ = startWorkers(0..<1, budget: budget, generation: 2, log: log)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let beforeRelease = await log.started
        #expect(beforeRelease == [], "the ceiling spans sessions")

        budget.release()
        await eventually { await log.started == [0] }
    }
}
