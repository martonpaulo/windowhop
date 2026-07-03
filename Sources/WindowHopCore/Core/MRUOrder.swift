import Foundation

/// Most-recently-used ordering. Index 0 is the currently focused item;
/// index 1 is the previously focused one (the switcher's initial selection).
/// New items enter at the end and move to the front when focused,
/// matching AltTab's lastFocusOrder semantics.
public struct MRUOrder<ID: Hashable> {
    public private(set) var ids: [ID] = []

    public init() {}

    /// Appends an item at the end if unknown. Returns true if it was added.
    @discardableResult
    public mutating func add(_ id: ID) -> Bool {
        guard !ids.contains(id) else { return false }
        ids.append(id)
        return true
    }

    /// Moves an item to the front (most recently used). Unknown items are inserted at the front.
    public mutating func focused(_ id: ID) {
        if let index = ids.firstIndex(of: id) {
            guard index != 0 else { return }
            ids.remove(at: index)
        }
        ids.insert(id, at: 0)
    }

    public mutating func remove(_ id: ID) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        }
    }

    public func contains(_ id: ID) -> Bool {
        ids.contains(id)
    }
}
