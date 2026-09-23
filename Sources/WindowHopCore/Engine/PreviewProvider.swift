import AppKit
import ScreenCaptureKit
import WindowHopKit

/// Window previews for the optional Window Previews appearance, tuned for an
/// instant-open feel (public APIs only):
///
/// - The cache lives in memory for the app's lifetime, so opening the switcher
///   shows the last known preview of every window IMMEDIATELY.
/// - Each session recaptures in parallel and delivers every result live: a
///   tile that opened with a cached snapshot crossfades to the fresh capture
///   the moment it lands, and tiles that had none fill in. Nothing is
///   captured while the switcher is closed.
/// - Images are requested already scaled to tile size (no full-resolution
///   retention), never written to disk, never transmitted, and evicted the
///   moment their window disappears — a late capture for a vanished window is
///   discarded (see PreviewLedger).
/// - Public ScreenCaptureKit only. AX windows are matched to SCWindows by
///   `PreviewMatcher` (pid + frame + decoration-tolerant title), and every
///   request receives a DISTINCT window — two windows of the same app can never
///   share a preview. When no unambiguous match exists the tile keeps its
///   placeholder and corner badge; a wrong preview is worse than none.
@MainActor
public final class PreviewProvider {
    public static let shared = PreviewProvider()

    /// The app's one `Preferences`, set once by `AppDelegate` (or the debug
    /// harness) before first use. It moves to the initializer when this type
    /// stops being a singleton (#108).
    public var preferences: Preferences!

    /// Delivered on the main thread for windows of the current session, keyed
    /// by the window's stable id (fill-ins and refreshes of cached snapshots).
    public var onPreview: ((AnyHashable, NSImage) -> Void)?
    /// Delivered on the main thread when no first snapshot can be produced for
    /// an item in the current session. Cached previews remain preferable and
    /// are never replaced by an unavailable state.
    public var onPreviewUnavailable: ((AnyHashable) -> Void)?
    /// One panel-level permission state; never repeated as a per-card action.
    public var onPermissionRequired: ((ScreenRecordingPermission.Status) -> Void)?
    /// A fresh dwell snapshot for the still-targeted window.
    public var onExpandedPreview: ((AnyHashable, NSImage) -> Void)?

    /// Decides what late, out-of-order capture results may do (pure, tested).
    private var ledger = PreviewLedger<AnyHashable>()
    private var cache: [AnyHashable: NSImage] = [:]
    /// The one dwell-sized snapshot of this session, for its latest target. It
    /// never enters `cache`: an expanded image is roughly nine times a tile's
    /// raster, and keeping one per visited window grew the app-lifetime cache
    /// by 132 MB after dwelling on 60 windows (measured in #87).
    private var expandedSnapshot: (id: AnyHashable, image: NSImage)?
    private var activeSessionGeneration: Int?
    /// The Screen Recording status of the open session. The preflight costs
    /// 14–18 ms on the main thread (measured in #120), so it is read once when
    /// the session opens and again only when a capture fails — the one signal
    /// that the grant may have changed — never per window that joins.
    private var sessionPermission: ScreenRecordingPermission.Status?
    /// The preflight read; replaced only by tests, which count the reads.
    var readPermissionStatus: () -> ScreenRecordingPermission.Status = {
        ScreenRecordingPermission.status
    }
    private var expandedGeneration = 0
    /// Every capture, of every path and session, takes a slot here first.
    private let captureBudget = CaptureBudget(limit: 4)

    struct CaptureRequest {
        let id: AnyHashable
        let pid: pid_t
        let title: String
        let frame: CGRect?
    }


    private init() {}

    // MARK: - Cache (memory-only, app lifetime, evicted with the window)

    public func cachedPreview(for id: AnyHashable) -> NSImage? {
        cache[id]
    }

    /// The sharpest snapshot available right now for the dwell presentation:
    /// this session's expanded capture of the target, else its tile snapshot.
    public func expandedPreview(for id: AnyHashable) -> NSImage? {
        if let expandedSnapshot, expandedSnapshot.id == id { return expandedSnapshot.image }
        return cache[id]
    }

    public func evict(_ id: AnyHashable) {
        cache[id] = nil
        if expandedSnapshot?.id == id { expandedSnapshot = nil }
        ledger.evict(id)
    }

    /// Whether a capture completing now would still be stored for this id.
    func ledgerShouldStoreForTesting(_ id: AnyHashable) -> Bool {
        ledger.shouldStore(id)
    }

    /// Seeds the cache the way a completed capture would, so lifetime tests can
    /// observe eviction without taking a real screenshot.
    func storeForTesting(_ image: NSImage, for id: AnyHashable) {
        cache[id] = image
    }

    /// Used when the user switches back to App Icons: nothing to retain.
    public func evictAll() {
        cache.removeAll()
        expandedSnapshot = nil
        ledger.evictAll()
    }

    // MARK: - Session lifecycle

    /// Starts recapturing previews for the session's items. No-op unless Window
    /// Previews mode is active and Screen Recording is granted. The caller
    /// passes the status it read when the session opened; the provider keeps
    /// it for the whole session.
    public func beginSession(items: [SwitcherItem], targetSize: CGSize, scale: CGFloat,
                             permissionStatus: ScreenRecordingPermission.Status) {
        guard preferences.appearanceMode == .windowPreviews else { return }
        guard permissionStatus.isAuthorized else {
            activeSessionGeneration = nil
            sessionPermission = nil
            onPermissionRequired?(permissionStatus)
            return
        }
        let requests = items.compactMap(makeCaptureRequest)
        let sessionGeneration = ledger.beginSession(ids: requests.map { $0.id })
        captureBudget.advance(to: sessionGeneration)
        activeSessionGeneration = sessionGeneration
        sessionPermission = permissionStatus
        guard !requests.isEmpty else { return }
        let pixelTarget = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        Task { [weak self] in
            await self?.capture(requests, generation: sessionGeneration,
                                pixelTarget: pixelTarget)
        }
    }

    /// Captures previews for windows that joined the list while the switcher is
    /// open. Scoped to the newcomers and to the session generation already in
    /// flight, so the tiles that are still filling in are left alone. No-op
    /// outside an active Window Previews session.
    public func extendSession(items: [SwitcherItem], targetSize: CGSize, scale: CGFloat) {
        guard preferences.appearanceMode == .windowPreviews,
              sessionPermission?.isAuthorized == true,
              let sessionGeneration = activeSessionGeneration else { return }
        let requests = items.compactMap(makeCaptureRequest)
        guard !requests.isEmpty else { return }
        ledger.extendSession(ids: requests.map { $0.id })
        let pixelTarget = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        Task { [weak self] in
            await self?.capture(requests, generation: sessionGeneration,
                                pixelTarget: pixelTarget)
        }
    }

    /// Stops live delivery; the cache stays warm for an instant next open.
    /// In-flight captures may still finish into the cache (free freshness),
    /// but no further capture work starts while the switcher is closed.
    public func endSession() {
        activeSessionGeneration = nil
        sessionPermission = nil
        cancelExpandedPreview()
        expandedSnapshot = nil
        ledger.endSession()
        captureBudget.advance(to: ledger.generation)
    }

    /// Requests a larger snapshot for the dwell presentation. It remains fully
    /// session-scoped and only delivers when both the session and target
    /// generation are still current.
    public func requestExpandedPreview(item: SwitcherItem,
                                       targetSize: CGSize,
                                       scale: CGFloat) {
        guard preferences.appearanceMode.supportsExpandedPreview,
              sessionPermission?.isAuthorized == true,
              let sessionGeneration = activeSessionGeneration,
              let request = makeCaptureRequest(item) else { return }
        expandedGeneration += 1
        let requestGeneration = expandedGeneration
        let pixelTarget = CGSize(width: targetSize.width * scale,
                                 height: targetSize.height * scale)
        Task { [weak self] in
            await self?.captureExpanded(
                request,
                sessionGeneration: sessionGeneration,
                requestGeneration: requestGeneration,
                pixelTarget: pixelTarget)
        }
    }

    public func cancelExpandedPreview() {
        expandedGeneration += 1
    }

    /// Hands a finished dwell capture to the presentation. The tile keeps the
    /// tile-sized image of its session capture; the expanded image replaces the
    /// previous one and lives at most until the session ends, so returning to
    /// the last expanded window is still sharp at once.
    func deliverExpandedSnapshot(_ image: NSImage, for id: AnyHashable) {
        expandedSnapshot = (id, image)
        onExpandedPreview?(id, image)
    }

    // MARK: - Capture

    /// One batch of tile captures. `TileCaptureFlow` owns the order: one
    /// shared lookup, captures in list order within the provider-wide budget,
    /// and one delayed retry per window per session for failures that can
    /// pass on their own (#91). Once the session ends, captures already
    /// running finish into the cache, but no further capture work starts.
    private func capture(_ requests: [CaptureRequest], generation sessionGeneration: Int,
                         pixelTarget: CGSize) async {
        let requestsByID = Dictionary(requests.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        await TileCaptureFlow.run(
            ids: requests.map(\.id),
            budget: captureBudget,
            generation: sessionGeneration,
            lookup: { ids -> [AnyHashable: SCWindow]? in
                guard let content = try? await SCShareableContent
                    .excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return nil }
                let assignments = PreviewMatcher.assign(
                    requests: ids.compactMap { requestsByID[$0] }.map(Self.matchRequest),
                    candidates: Self.matchCandidates(in: content.windows))
                return assignments.mapValues { content.windows[$0] }
            },
            capture: { scWindow in
                await self.captureImage(scWindow, pixelTarget: pixelTarget)
            },
            isCurrent: { self.isTileSessionCurrent(sessionGeneration) },
            claimRetries: { ids in
                self.claimRetries(ids, generation: sessionGeneration)
            },
            sleep: { duration in try? await Task.sleep(for: duration) },
            deliver: { id, image in
                self.storeTileSnapshot(image, for: id, generation: sessionGeneration)
            },
            unavailable: { ids in
                self.markUnavailable(ids, generation: sessionGeneration)
            })
    }

    private func storeTileSnapshot(_ image: NSImage, for id: AnyHashable,
                                   generation sessionGeneration: Int) {
        // the ledger is the single authority on what a late result may do:
        // nothing for vanished windows, cache-only for ended sessions
        guard ledger.shouldStore(id) else { return }
        cache[id] = image
        if ledger.shouldDeliver(id, capturedIn: sessionGeneration) {
            onPreview?(id, image)
        }
    }

    /// True while tile capture work for this session may still start: the same
    /// session, still in Window Previews, with the grant it opened with.
    private func isTileSessionCurrent(_ sessionGeneration: Int) -> Bool {
        activeSessionGeneration == sessionGeneration
            && preferences.appearanceMode == .windowPreviews
            && sessionPermission?.isAuthorized == true
    }

    /// Hands out the one retry each window gets per session. A failure is the
    /// signal that the grant may have changed, so the status is confirmed once
    /// for the whole batch first: a revoked grant blocks the panel instead of
    /// spending a retry.
    func claimRetries(_ ids: [AnyHashable], generation sessionGeneration: Int)
        -> [AnyHashable] {
        let status = readPermissionStatus()
        guard status.isAuthorized else {
            sessionPermission = status
            onPermissionRequired?(status)
            return []
        }
        let claimed = ids.filter { ledger.claimRetry($0, capturedIn: sessionGeneration) }
        if !claimed.isEmpty {
            Log.previews.debug("retrying \(claimed.count, privacy: .public) failed tile captures")
        }
        return claimed
    }

    private func captureExpanded(_ request: CaptureRequest,
                                 sessionGeneration: Int,
                                 requestGeneration: Int,
                                 pixelTarget: CGSize) async {
        let id = request.id
        await ExpandedCaptureFlow.run(
            lookup: { () -> SCWindow? in
                guard let content = try? await SCShareableContent
                    .excludingDesktopWindows(false, onScreenWindowsOnly: false),
                    let candidateIndex = PreviewMatcher.assign(
                        requests: [Self.matchRequest(request)],
                        candidates: Self.matchCandidates(in: content.windows))[request.id]
                else { return nil }
                return content.windows[candidateIndex]
            },
            isCurrent: {
                self.isExpandedRequestCurrent(id,
                                              sessionGeneration: sessionGeneration,
                                              requestGeneration: requestGeneration)
            },
            capture: { scWindow in
                // waiting for a slot can outlast the request, so check again
                // before spending the capture
                guard await self.captureBudget.acquire(generation: sessionGeneration,
                                                       jumpingQueue: true) else {
                    return nil
                }
                defer { self.captureBudget.release() }
                guard self.isExpandedRequestCurrent(id,
                                                    sessionGeneration: sessionGeneration,
                                                    requestGeneration: requestGeneration),
                    case .captured(let image) = await self.captureImage(
                        scWindow, pixelTarget: pixelTarget)
                else { return nil }
                return image
            },
            deliver: { image in
                self.deliverExpandedSnapshot(image, for: id)
            })
    }

    /// True while this expanded request may still spend capture work and
    /// deliver: same session, same request, and a target the ledger still owns.
    private func isExpandedRequestCurrent(_ id: AnyHashable,
                                          sessionGeneration: Int,
                                          requestGeneration: Int) -> Bool {
        activeSessionGeneration == sessionGeneration
            && expandedGeneration == requestGeneration
            && ledger.shouldDeliver(id, capturedIn: sessionGeneration)
    }

    private func captureImage(_ scWindow: SCWindow,
                              pixelTarget: CGSize) async -> TileCaptureResult<NSImage> {
        let windowSize = scWindow.frame.size
        guard windowSize.width > 1, windowSize.height > 1 else { return .failed(.invalidTarget) }
        let configuration = SCStreamConfiguration()
        let fit = min(pixelTarget.width / windowSize.width,
                      pixelTarget.height / windowSize.height, 2)
        configuration.width = max(1, Int(windowSize.width * fit))
        configuration.height = max(1, Int(windowSize.height * fit))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
        } catch {
            let failure = Self.failure(for: error)
            let code = (error as NSError).code
            Log.previews.debug(
                "tile capture failed: \(String(describing: failure), privacy: .public) (\(code, privacy: .public))")
            return .failed(failure)
        }
        return .captured(NSImage(cgImage: cgImage,
                                 size: NSSize(width: CGFloat(cgImage.width) / 2,
                                              height: CGFloat(cgImage.height) / 2)))
    }

    /// Keeps the capture error's meaning instead of discarding it. Only errors
    /// that describe a broken connection or a system hiccup are transient;
    /// anything unknown is treated as stable, so it never starts a retry.
    /// Codes: ScreenCaptureKit `SCError.h` (macOS 27 SDK).
    static func failure(for error: any Error) -> PreviewFailure {
        guard let streamError = error as? SCStreamError else {
            return .captureFailed(transient: false)
        }
        switch streamError.code {
        case .userDeclined:
            return .permissionDenied
        case .internalError, .failedApplicationConnectionInterrupted,
             .failedApplicationConnectionInvalid, .noWindowList, .systemStoppedStream:
            return .captureFailed(transient: true)
        default:
            return .captureFailed(transient: false)
        }
    }

    private func makeCaptureRequest(_ item: SwitcherItem) -> CaptureRequest? {
        guard let window = item.window else { return nil }
        if let native = window.nativeWindow, let primary = NSScreen.screens.first {
            let frame = native.frame
            return CaptureRequest(id: item.id,
                                  pid: ProcessInfo.processInfo.processIdentifier,
                                  title: item.title,
                                  frame: CGRect(x: frame.origin.x,
                                                y: primary.frame.maxY - frame.maxY,
                                                width: frame.width,
                                                height: frame.height))
        }
        guard let app = window.app else { return nil }
        return CaptureRequest(id: item.id, pid: app.pid,
                              title: item.title, frame: window.frame)
    }

    /// Reports one batch of failed ids. A failure is the only event that can
    /// reveal a changed grant, so the batch re-reads the status once: a revoked
    /// grant switches the panel to its permission-blocked state (#51) instead
    /// of marking cards unavailable one by one.
    func markUnavailable(_ ids: [AnyHashable], generation sessionGeneration: Int) {
        guard activeSessionGeneration == sessionGeneration,
              sessionPermission?.isAuthorized == true else { return }
        let status = readPermissionStatus()
        guard status.isAuthorized else {
            sessionPermission = status
            onPermissionRequired?(status)
            return
        }
        for id in ids where cache[id] == nil
            && ledger.shouldDeliver(id, capturedIn: sessionGeneration) {
            onPreviewUnavailable?(id)
        }
    }

    /// The status the open session uses, nil outside a Window Previews session.
    var sessionPermissionForTesting: ScreenRecordingPermission.Status? {
        sessionPermission
    }

    /// The generation of the open session, nil when none is open.
    var sessionGenerationForTesting: Int? {
        activeSessionGeneration
    }

    // MARK: - Diagnostics

    /// Reports the pairing the next session would use, for the `--dump-previews`
    /// harness flag: no capture is requested, so no image is produced, cached, or
    /// written anywhere. Window titles are printed for the person running it.
    public func dumpMatching(items: [SwitcherItem],
                             completion: @escaping ([String]) -> Void) {
        let requests = items.compactMap(makeCaptureRequest)
        Task {
            guard let content = try? await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
                completion(["dump-previews: no shareable content"])
                return
            }
            let candidates = Self.matchCandidates(in: content.windows)
            let assignments = PreviewMatcher.assign(requests: requests.map(Self.matchRequest),
                                                    candidates: candidates)
            let lines = requests.map { request -> String in
                guard let index = assignments[request.id] else {
                    return "· \(request.title) [pid \(request.pid)] → no unambiguous window (placeholder)"
                }
                let window = content.windows[index]
                return "✓ \(request.title) [pid \(request.pid)] → \"\(window.title ?? "")\" \(window.frame)"
            }
            completion(lines)
        }
    }

    // MARK: - Matching

    /// SCWindows are paired with switcher entries by `PreviewMatcher` (pure,
    /// unit-tested): a unique, unambiguous assignment, never a guess.
    private static func matchCandidates(in windows: [SCWindow]) -> [PreviewMatcher.Candidate] {
        windows.enumerated().map { index, window in
            PreviewMatcher.Candidate(index: index,
                                     pid: window.owningApplication?.processID ?? -1,
                                     title: window.title ?? "",
                                     frame: window.frame)
        }
    }

    private static func matchRequest(_ request: CaptureRequest) -> PreviewMatcher.Request {
        PreviewMatcher.Request(id: request.id, pid: request.pid,
                               title: request.title, frame: request.frame)
    }
}
