import Foundation

/// Pure dwell bookkeeping for the non-activating preview shown inside
/// WindowHop. Generations make expired rapid-navigation requests harmless.
public struct ExpandedPreviewSession<ID: Hashable> {
    public struct Request: Equatable {
        public let windowID: ID
        public let generation: Int
    }

    public private(set) var targetedWindowID: ID?
    public private(set) var expandedWindowID: ID?
    private var generation = 0

    public init() {}

    public mutating func begin(targetedWindowID: ID?) -> Request? {
        generation += 1
        self.targetedWindowID = nil
        expandedWindowID = nil
        return target(targetedWindowID)
    }

    /// Re-targeting the window that is already targeted is a no-op: a store
    /// refresh that preserves the selection must neither restart dwell nor
    /// invalidate the request already in flight.
    public mutating func target(_ windowID: ID?) -> Request? {
        if targetedWindowID == windowID { return nil }
        targetedWindowID = windowID
        expandedWindowID = nil
        generation += 1
        guard let windowID else { return nil }
        return Request(windowID: windowID, generation: generation)
    }

    public mutating func settle(_ request: Request, availableWindowIDs: Set<ID>) -> ID? {
        guard request.generation == generation,
              targetedWindowID == request.windowID,
              availableWindowIDs.contains(request.windowID) else { return nil }
        expandedWindowID = request.windowID
        return request.windowID
    }

    public mutating func retainAvailable(_ availableWindowIDs: Set<ID>) {
        if let targetedWindowID, !availableWindowIDs.contains(targetedWindowID) {
            self.targetedWindowID = nil
            generation += 1
        }
        if let expandedWindowID, !availableWindowIDs.contains(expandedWindowID) {
            self.expandedWindowID = nil
        }
    }

    public mutating func reset() {
        generation += 1
        targetedWindowID = nil
        expandedWindowID = nil
    }
}
