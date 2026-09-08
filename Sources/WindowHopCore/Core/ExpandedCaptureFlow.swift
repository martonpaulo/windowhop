import Foundation

/// The ordering rule for one expanded-preview capture.
///
/// Expanded capture is strictly session-scoped: the session that asked for the
/// image may end while the shareable-content lookup is still pending, and no
/// screenshot may start after that. Rejecting the result afterwards is not
/// enough — the capture must never begin. The same check runs again after the
/// capture, because a session can also end while the screenshot is in flight.
///
/// The rule lives here, free of any capture framework, so both boundaries are
/// provable without touching the screen. `Engine/PreviewProvider` supplies the
/// real lookup, capture and delivery stages.
public enum ExpandedCaptureFlow {
    public enum Outcome: Equatable {
        case delivered
        case noCandidate
        /// The session, target or request became obsolete during lookup, so no
        /// screenshot was requested at all.
        case cancelledBeforeCapture
        case captureFailed
        /// The capture had already started; its result is discarded.
        case cancelledAfterCapture
    }

    @discardableResult
    public static func run<Candidate, Image>(
        lookup: () async -> Candidate?,
        isCurrent: @MainActor @Sendable () -> Bool,
        capture: (Candidate) async -> Image?,
        deliver: @MainActor @Sendable (Image) -> Void
    ) async -> Outcome {
        guard let candidate = await lookup() else { return .noCandidate }
        guard await MainActor.run(body: isCurrent) else { return .cancelledBeforeCapture }
        guard let image = await capture(candidate) else { return .captureFailed }
        guard await MainActor.run(body: isCurrent) else { return .cancelledAfterCapture }
        await MainActor.run { deliver(image) }
        return .delivered
    }
}
