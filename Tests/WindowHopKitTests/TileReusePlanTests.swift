import Foundation
import Testing

@testable import WindowHopKit

/// A list refresh must redraw only the tiles whose data changed (#119): each
/// window keeps its tile, and only changed or new windows are configured.
struct TileReusePlanTests {
    private typealias Entry = (id: String, content: String)

    private func plan(_ current: [Entry?], _ items: [Entry]) -> TileReusePlan {
        TileReusePlan.make(current: current, items: items)
    }

    private func assignment(_ slot: Int, configure: Bool) -> TileReusePlan.Assignment {
        TileReusePlan.Assignment(slot: slot, needsConfigure: configure)
    }

    @Test func unchangedListReconfiguresNothing() {
        let result = plan([("a", "A"), ("b", "B")], [("a", "A"), ("b", "B")])
        #expect(
            result.assignments == [
                assignment(0, configure: false),
                assignment(1, configure: false),
            ])
        #expect(result.unusedSlots == [])
    }

    @Test func onlyTheChangedWindowIsReconfigured() {
        let result = plan(
            [("a", "A"), ("b", "B"), ("c", "C")],
            [("a", "A"), ("b", "B renamed"), ("c", "C")])
        #expect(result.assignments.map(\.needsConfigure) == [false, true, false])
        #expect(result.assignments.map(\.slot) == [0, 1, 2])
    }

    @Test func reorderedWindowsMoveWithTheirTiles() {
        let result = plan([("a", "A"), ("b", "B")], [("b", "B"), ("a", "A")])
        #expect(
            result.assignments == [
                assignment(1, configure: false),
                assignment(0, configure: false),
            ])
    }

    @Test func removedWindowFreesItsSlotAndTheRestShift() {
        let result = plan([("a", "A"), ("b", "B"), ("c", "C")], [("a", "A"), ("c", "C")])
        #expect(
            result.assignments == [
                assignment(0, configure: false),
                assignment(2, configure: false),
            ])
        #expect(result.unusedSlots == [1])
    }

    @Test func newWindowTakesTheFirstFreeSlotAndIsConfigured() {
        let result = plan([("a", "A"), nil, ("gone", "G")], [("a", "A"), ("new", "N")])
        #expect(
            result.assignments == [
                assignment(0, configure: false),
                assignment(1, configure: true),
            ])
        #expect(result.unusedSlots == [2])
    }

    @Test func poolGrowsBeyondItsSizeWhenNoSlotIsFree() {
        let result = plan([("a", "A")], [("a", "A"), ("b", "B"), ("c", "C")])
        #expect(
            result.assignments == [
                assignment(0, configure: false),
                assignment(1, configure: true),
                assignment(2, configure: true),
            ])
        #expect(result.unusedSlots == [])
    }

    @Test func unknownSlotsAreAlwaysConfigured() {
        // a released tile reports nil: a new session reconfigures everything
        let result = plan([nil, nil], [("a", "A"), ("b", "B")])
        #expect(
            result.assignments == [
                assignment(0, configure: true),
                assignment(1, configure: true),
            ])
    }

    @Test func duplicateIdReusesTheTileOnlyOnce() {
        let result = plan([("a", "A"), nil], [("a", "A"), ("a", "A")])
        #expect(
            result.assignments == [
                assignment(0, configure: false),
                assignment(1, configure: true),
            ])
    }

    @Test func everySlotIsEitherAssignedOrUnused() {
        let current: [Entry?] = [("a", "A"), ("b", "B"), nil, ("d", "D"), ("e", "E")]
        let result = plan(current, [("e", "E"), ("x", "X"), ("b", "B2")])
        let slots = result.assignments.map(\.slot) + result.unusedSlots
        #expect(slots.sorted() == Array(0..<current.count))
    }
}
