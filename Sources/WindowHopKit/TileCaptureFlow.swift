import Foundation

/// Why a tile capture produced no snapshot. Only a failure that can pass on
/// its own is worth a retry; the others describe a stable state.
public enum PreviewFailure: Equatable, Sendable {
    /// The shared window inventory could not be read.
    case lookupFailed
    /// No window matches the entry unambiguously; a guess would be wrong.
    case noMatch
    /// The matched window has no drawable area (a frame of 1 pt or less).
    case invalidTarget
    /// The capture API reported that the user declined Screen Recording.
    case permissionDenied
    /// The capture API failed; `transient` holds only for errors that describe
    /// an interrupted connection or a system hiccup rather than the target.
    case captureFailed(transient: Bool)
}

/// The bounded recovery rule for tile captures (#91). AltTab does not retry
/// (`WindowCaptureEvents.swift` logs the error and stops); this retry is
/// WindowHop's own.
public enum PreviewRetryPolicy {
    /// How long a transient failure waits before its one retry. Our own value,
    /// short enough for the retry to land inside a typical 1-3 s session.
    public static let delay: Duration = .milliseconds(500)

    public static func isRetryable(_ failure: PreviewFailure) -> Bool {
        switch failure {
        case .lookupFailed, .captureFailed(transient: true): true
        case .noMatch, .invalidTarget, .permissionDenied, .captureFailed(transient: false): false
        }
    }
}

public enum TileCaptureResult<Image> {
    case captured(Image)
    case failed(PreviewFailure)
}

/// The ordering rule for one batch of tile captures: one shared lookup, the
/// captures in list order within the provider-wide budget, and at most one
/// delayed, coalesced retry for the failures that may pass on their own.
///
/// Free of any capture framework, so attempt counts, cancellation and recovery
/// are provable with fakes. `Engine/PreviewProvider` supplies the real stages.
@MainActor
public enum TileCaptureFlow {
    // Ten parameters: each stage is its own injected seam, so the flow is provable
    // with fakes; `run` suppresses function_parameter_count for that reason (#97).
    /// - Parameters:
    ///   - lookup: matches every id to a capture target in one inventory read;
    ///     nil when the inventory could not be read, a missing id has no match.
    ///   - isCurrent: true while the session may still spend capture work.
    ///   - claimRetries: the ids that may use their one retry now.
    ///   - deliver: every captured image; the caller decides whether it still
    ///     reaches the cache and the panel.
    ///   - unavailable: ids whose failure is final for this session.
    public static func run<ID: Hashable, Candidate, Image>(  // swiftlint:disable:this function_parameter_count
        ids: [ID],
        budget: CaptureBudget,
        generation: Int,
        lookup: @MainActor ([ID]) async -> [ID: Candidate]?,
        capture: @escaping @MainActor (Candidate) async -> TileCaptureResult<Image>,
        isCurrent: () -> Bool,
        claimRetries: ([ID]) -> [ID],
        sleep: (Duration) async -> Void,
        deliver: @escaping @MainActor (ID, Image) -> Void,
        unavailable: ([ID]) -> Void
    ) async {
        guard
            let failures = await attempt(
                ids, budget: budget, generation: generation,
                lookup: lookup, capture: capture,
                isCurrent: isCurrent, deliver: deliver)
        else { return }
        let final = failures.filter { !PreviewRetryPolicy.isRetryable($0.failure) }.map(\.id)
        let retryable = failures.filter { PreviewRetryPolicy.isRetryable($0.failure) }.map(\.id)
        if !final.isEmpty { unavailable(final) }
        // the retryable tiles keep their loading state while they wait
        guard !retryable.isEmpty, isCurrent() else { return }
        await sleep(PreviewRetryPolicy.delay)
        guard isCurrent() else { return }
        let claimed = claimRetries(retryable)
        let claimedSet = Set(claimed)
        let refused = retryable.filter { !claimedSet.contains($0) }
        if !refused.isEmpty { unavailable(refused) }
        guard !claimed.isEmpty,
            let retryFailures = await attempt(
                claimed, budget: budget, generation: generation,
                lookup: lookup, capture: capture,
                isCurrent: isCurrent, deliver: deliver),
            !retryFailures.isEmpty
        else { return }
        unavailable(retryFailures.map(\.id))
    }

    /// One lookup and one capture per matched id. Returns the failures, or nil
    /// when the session stopped before every capture could start.
    private static func attempt<ID: Hashable, Candidate, Image>(
        _ ids: [ID],
        budget: CaptureBudget,
        generation: Int,
        lookup: @MainActor ([ID]) async -> [ID: Candidate]?,
        capture: @escaping @MainActor (Candidate) async -> TileCaptureResult<Image>,
        isCurrent: () -> Bool,
        deliver: @escaping @MainActor (ID, Image) -> Void
    ) async -> [(id: ID, failure: PreviewFailure)]? {
        guard let matched = await lookup(ids) else {
            return ids.map { ($0, .lookupFailed) }
        }
        var failures: [(id: ID, failure: PreviewFailure)] =
            ids
            .filter { matched[$0] == nil }
            .map { ($0, .noMatch) }
        // parallel, in list order, within the provider-wide budget. The tasks
        // run on main between their awaits; the captures themselves proceed in
        // parallel. A capture that already started finishes and delivers.
        var captures: [(id: ID, task: Task<PreviewFailure?, Never>)] = []
        var stopped = false
        for id in ids {
            guard let candidate = matched[id] else { continue }
            guard await budget.acquire(generation: generation) else {
                stopped = true
                break
            }
            guard isCurrent() else {
                budget.release()
                stopped = true
                break
            }
            captures.append(
                (
                    id,
                    Task {
                        defer { budget.release() }
                        switch await capture(candidate) {
                        case .captured(let image):
                            deliver(id, image)
                            return nil
                        case .failed(let failure):
                            return failure
                        }
                    }
                ))
        }
        for (id, task) in captures {
            if let failure = await task.value { failures.append((id, failure)) }
        }
        return stopped ? nil : failures
    }
}
