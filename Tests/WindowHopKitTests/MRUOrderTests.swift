import Foundation
import Testing

@testable import WindowHopKit

struct MRUOrderTests {
    @Test func newItemsAppendAtEnd() {
        var mru = MRUOrder<String>()
        mru.add("a")
        mru.add("b")
        #expect(mru.ids == ["a", "b"])
    }

    @Test func addingKnownItemIsIgnored() {
        var mru = MRUOrder<String>()
        mru.add("a")
        #expect(mru.add("a") == false)
        #expect(mru.ids == ["a"])
    }

    @Test func focusMovesToFront() {
        var mru = MRUOrder<String>()
        mru.add("a")
        mru.add("b")
        mru.add("c")
        mru.focused("c")
        #expect(mru.ids == ["c", "a", "b"])
        mru.focused("a")
        #expect(mru.ids == ["a", "c", "b"])
    }

    @Test func focusUnknownInsertsAtFront() {
        var mru = MRUOrder<String>()
        mru.add("a")
        mru.focused("x")
        #expect(mru.ids == ["x", "a"])
    }

    @Test func readdingAfterRemovalAppendsAtEnd() {
        var mru = MRUOrder<String>()
        mru.add("a")
        mru.add("b")
        mru.remove("a")
        #expect(mru.add("a") == true)
        #expect(mru.ids == ["b", "a"])
    }

    @Test func focusingTheFrontItemIsANoOp() {
        var mru = MRUOrder<String>()
        mru.add("a")
        mru.add("b")
        mru.focused("a")
        #expect(mru.ids == ["a", "b"])
    }

    @Test func remove() {
        var mru = MRUOrder<String>()
        mru.add("a")
        mru.add("b")
        mru.remove("a")
        #expect(mru.ids == ["b"])
        mru.remove("missing")
        #expect(mru.ids == ["b"])
    }
}
