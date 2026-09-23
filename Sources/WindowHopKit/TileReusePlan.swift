/// Decides how a list refresh maps onto the switcher's pooled tiles, so only
/// tiles whose data changed are reconfigured.
///
/// The panel keeps one pool of tiles and the invariant "pool slot i shows
/// item i". Reconfiguring every tile on every refresh made a burst of window
/// events (a window dragged at 60 Hz) cost a full redraw of 100+ tiles per
/// event (#119). This plan keys tiles by window id instead: a window that is
/// still listed keeps its tile, and that tile is reconfigured only when the
/// data it shows changed. A reordered window moves with its tile. Only new
/// windows take a free tile, which then always needs configuring.
///
/// `Content` is whatever the tile renders (title, icon, state, appearance);
/// the caller defines it, so presentation types stay out of this target.
public struct TileReusePlan: Equatable, Sendable {
    public struct Assignment: Equatable, Sendable {
        /// The pool slot whose tile shows this item. Slots at or beyond the
        /// current pool size are tiles the caller must create.
        public var slot: Int
        /// The tile's content differs from the item's, or the tile showed no
        /// item or another window before.
        public var needsConfigure: Bool

        public init(slot: Int, needsConfigure: Bool) {
            self.slot = slot
            self.needsConfigure = needsConfigure
        }
    }

    /// One entry per new item, in item order.
    public var assignments: [Assignment]
    /// Pool slots that no item uses any more, in ascending order. Their tiles
    /// are hidden and follow the assigned tiles in the new pool order.
    public var unusedSlots: [Int]

    public init(assignments: [Assignment], unusedSlots: [Int]) {
        self.assignments = assignments
        self.unusedSlots = unusedSlots
    }

    /// - Parameters:
    ///   - current: what each pool slot shows now, in slot order; nil for a
    ///     hidden slot or one whose content is unknown (it is configured
    ///     again before use).
    ///   - items: the refreshed list, in display order.
    public static func make<ID: Hashable, Content: Equatable>(
        current: [(id: ID, content: Content)?],
        items: [(id: ID, content: Content)]
    ) -> TileReusePlan {
        var slotById: [ID: Int] = [:]
        for (slot, entry) in current.enumerated() {
            guard let entry, slotById[entry.id] == nil else { continue }
            slotById[entry.id] = slot
        }
        var used = Set<Int>()
        var assignments = [Assignment?](repeating: nil, count: items.count)
        for (index, item) in items.enumerated() {
            // a duplicate id in the new list keeps the tile only for its first use
            guard let slot = slotById[item.id], !used.contains(slot) else { continue }
            used.insert(slot)
            assignments[index] = Assignment(
                slot: slot, needsConfigure: current[slot]?.content != item.content)
        }
        // new windows take free slots in ascending order, then fresh tiles
        var free = (0..<current.count).filter { !used.contains($0) }.makeIterator()
        var nextFresh = current.count
        var unused = Set((0..<current.count).filter { !used.contains($0) })
        for index in items.indices where assignments[index] == nil {
            let slot: Int
            if let reusable = free.next() {
                slot = reusable
                unused.remove(reusable)
            } else {
                slot = nextFresh
                nextFresh += 1
            }
            assignments[index] = Assignment(slot: slot, needsConfigure: true)
        }
        return TileReusePlan(
            assignments: assignments.compactMap { $0 },
            unusedSlots: unused.sorted())
    }
}
