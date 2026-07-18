import Foundation

/// Pure bookkeeping for showing a targeted window before the user commits a
/// switch. Stable window identities keep same-app and duplicate-title windows
/// distinct, while request generations discard rapid-navigation work that has
/// already been superseded.
public struct TemporaryActivationSession<ID: Hashable> {
    /// Long enough to skip fast key-repeat traversal, short enough to feel
    /// immediate when the user pauses on a window.
    public static var navigationSettleDelay: TimeInterval { 0.18 }
    /// AX focus notifications can trail a completed action; compare event time
    /// against this grace window rather than running any idle timer.
    public static var lateFocusGraceDuration: TimeInterval { 1 }

    public struct Request: Equatable {
        public let windowID: ID
        public let generation: Int
    }

    public private(set) var originWindowID: ID?
    public private(set) var targetedWindowID: ID?
    public private(set) var temporarilyActiveWindowID: ID?
    public private(set) var committedWindowID: ID?
    private var generation = 0

    public init() {}

    /// Starts a session. The initially highlighted entry is a real target and
    /// may be shown once navigation settles.
    public mutating func begin(originWindowID: ID?, targetedWindowID: ID?) -> Request? {
        generation += 1
        self.originWindowID = originWindowID
        self.targetedWindowID = nil
        temporarilyActiveWindowID = nil
        committedWindowID = nil
        return target(targetedWindowID)
    }

    /// Updates the highlighted target. Returning a request lets the caller
    /// debounce activation; selecting an already visible window needs no work.
    public mutating func target(_ windowID: ID?) -> Request? {
        if targetedWindowID == windowID {
            guard let windowID, windowID != temporarilyActiveWindowID else { return nil }
            generation += 1
            return Request(windowID: windowID, generation: generation)
        }
        targetedWindowID = windowID
        generation += 1
        guard let windowID, windowID != temporarilyActiveWindowID else { return nil }
        return Request(windowID: windowID, generation: generation)
    }

    /// A modal surface temporarily took focus away from both the origin and the
    /// shown target. The highlighted target remains valid and can be requested
    /// again after the interruption ends.
    public mutating func interruptTemporaryActivation() {
        temporarilyActiveWindowID = nil
        generation += 1
    }

    /// Accepts a settled request only when it is still current and the window
    /// still exists. Older rapid-navigation requests become harmless no-ops.
    public mutating func settle(_ request: Request, availableWindowIDs: Set<ID>) -> ID? {
        guard request.generation == generation,
              targetedWindowID == request.windowID,
              availableWindowIDs.contains(request.windowID) else { return nil }
        temporarilyActiveWindowID = request.windowID
        return request.windowID
    }

    /// Removes identities that disappeared during the session. The controller
    /// supplies a valid neighboring target after its list state is reconciled.
    public mutating func retainAvailable(_ availableWindowIDs: Set<ID>) {
        if let originWindowID, !availableWindowIDs.contains(originWindowID) {
            self.originWindowID = nil
        }
        if let targetedWindowID, !availableWindowIDs.contains(targetedWindowID) {
            self.targetedWindowID = nil
            generation += 1
        }
        if let temporarilyActiveWindowID,
           !availableWindowIDs.contains(temporarilyActiveWindowID) {
            self.temporarilyActiveWindowID = nil
        }
    }

    /// Records the final choice. This is the only operation that creates a
    /// committed-window identity.
    public mutating func commit(_ windowID: ID?, availableWindowIDs: Set<ID>) -> ID? {
        guard let windowID, availableWindowIDs.contains(windowID) else {
            committedWindowID = nil
            return nil
        }
        committedWindowID = windowID
        return windowID
    }

    /// Returns the exact origin when it still exists. No best-guess window is
    /// substituted because that could unexpectedly activate unrelated content.
    public mutating func cancel(availableWindowIDs: Set<ID>) -> ID? {
        committedWindowID = nil
        guard let originWindowID, availableWindowIDs.contains(originWindowID) else { return nil }
        return originWindowID
    }

    public mutating func reset() {
        generation += 1
        originWindowID = nil
        targetedWindowID = nil
        temporarilyActiveWindowID = nil
        committedWindowID = nil
    }
}
