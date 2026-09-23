import XCTest
@testable import WindowHopKit

/// A list refresh must redraw only the tiles whose data changed (#119): each
/// window keeps its tile, and only changed or new windows are configured.
final class TileReusePlanTests: XCTestCase {
    private typealias Entry = (id: String, content: String)

    private func plan(_ current: [Entry?], _ items: [Entry]) -> TileReusePlan {
        TileReusePlan.make(current: current, items: items)
    }

    private func assignment(_ slot: Int, configure: Bool) -> TileReusePlan.Assignment {
        TileReusePlan.Assignment(slot: slot, needsConfigure: configure)
    }

    func testUnchangedListReconfiguresNothing() {
        let result = plan([("a", "A"), ("b", "B")], [("a", "A"), ("b", "B")])
        XCTAssertEqual(result.assignments, [assignment(0, configure: false),
                                            assignment(1, configure: false)])
        XCTAssertEqual(result.unusedSlots, [])
    }

    func testOnlyTheChangedWindowIsReconfigured() {
        let result = plan([("a", "A"), ("b", "B"), ("c", "C")],
                          [("a", "A"), ("b", "B renamed"), ("c", "C")])
        XCTAssertEqual(result.assignments.map(\.needsConfigure), [false, true, false])
        XCTAssertEqual(result.assignments.map(\.slot), [0, 1, 2])
    }

    func testReorderedWindowsMoveWithTheirTiles() {
        let result = plan([("a", "A"), ("b", "B")], [("b", "B"), ("a", "A")])
        XCTAssertEqual(result.assignments, [assignment(1, configure: false),
                                            assignment(0, configure: false)])
    }

    func testRemovedWindowFreesItsSlotAndTheRestShift() {
        let result = plan([("a", "A"), ("b", "B"), ("c", "C")], [("a", "A"), ("c", "C")])
        XCTAssertEqual(result.assignments, [assignment(0, configure: false),
                                            assignment(2, configure: false)])
        XCTAssertEqual(result.unusedSlots, [1])
    }

    func testNewWindowTakesTheFirstFreeSlotAndIsConfigured() {
        let result = plan([("a", "A"), nil, ("gone", "G")], [("a", "A"), ("new", "N")])
        XCTAssertEqual(result.assignments, [assignment(0, configure: false),
                                            assignment(1, configure: true)])
        XCTAssertEqual(result.unusedSlots, [2])
    }

    func testPoolGrowsBeyondItsSizeWhenNoSlotIsFree() {
        let result = plan([("a", "A")], [("a", "A"), ("b", "B"), ("c", "C")])
        XCTAssertEqual(result.assignments, [assignment(0, configure: false),
                                            assignment(1, configure: true),
                                            assignment(2, configure: true)])
        XCTAssertEqual(result.unusedSlots, [])
    }

    func testUnknownSlotsAreAlwaysConfigured() {
        // a released tile reports nil: a new session reconfigures everything
        let result = plan([nil, nil], [("a", "A"), ("b", "B")])
        XCTAssertEqual(result.assignments, [assignment(0, configure: true),
                                            assignment(1, configure: true)])
    }

    func testDuplicateIdReusesTheTileOnlyOnce() {
        let result = plan([("a", "A"), nil], [("a", "A"), ("a", "A")])
        XCTAssertEqual(result.assignments, [assignment(0, configure: false),
                                            assignment(1, configure: true)])
    }

    func testEverySlotIsEitherAssignedOrUnused() {
        let current: [Entry?] = [("a", "A"), ("b", "B"), nil, ("d", "D"), ("e", "E")]
        let result = plan(current, [("e", "E"), ("x", "X"), ("b", "B2")])
        let slots = result.assignments.map(\.slot) + result.unusedSlots
        XCTAssertEqual(slots.sorted(), Array(0..<current.count))
    }
}
