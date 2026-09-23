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
    /// Previews mode is active and Screen Recording is granted.
    public func beginSession(items: [SwitcherItem], targetSize: CGSize, scale: CGFloat) {
        guard Preferences.shared.appearanceMode == .windowPreviews else { return }
        let permissionStatus = ScreenRecordingPermission.status
        guard permissionStatus.isAuthorized else {
            activeSessionGeneration = nil
            onPermissionRequired?(permissionStatus)
            return
        }
        let requests = items.compactMap(makeCaptureRequest)
        let sessionGeneration = ledger.beginSession(ids: requests.map { $0.id })
        captureBudget.advance(to: sessionGeneration)
        activeSessionGeneration = sessionGeneration
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
        guard Preferences.shared.appearanceMode == .windowPreviews,
              ScreenRecordingPermission.status.isAuthorized,
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
        guard Preferences.shared.appearanceMode.supportsExpandedPreview,
              ScreenRecordingPermission.status.isAuthorized,
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

    private func capture(_ requests: [CaptureRequest], generation sessionGeneration: Int,
                         pixelTarget: CGSize) async {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            for request in requests {
                markUnavailable(request.id, generation: sessionGeneration)
            }
            return
        }
        let assignments = PreviewMatcher.assign(
            requests: requests.map(Self.matchRequest),
            candidates: Self.matchCandidates(in: content.windows))
        let assigned = requests.compactMap { request in
            assignments[request.id].map { (request, content.windows[$0]) }
        }
        let assignedIDs = Set(assigned.map { $0.0.id })
        for request in requests where !assignedIDs.contains(request.id) {
            markUnavailable(request.id, generation: sessionGeneration)
        }
        // parallel, in list order, within the provider-wide budget: fast without
        // saturating WindowServer. The tasks run on main between their awaits;
        // the screenshots themselves proceed in parallel inside ScreenCaptureKit.
        // Once the session ends, captures already running finish into the
        // cache, but no further capture work starts.
        let budget = captureBudget
        var captures: [Task<Void, Never>] = []
        for (request, scWindow) in assigned {
            guard await budget.acquire(generation: sessionGeneration) else { break }
            captures.append(Task { [weak self] in
                defer { budget.release() }
                await self?.captureOne(request, scWindow, generation: sessionGeneration,
                                       pixelTarget: pixelTarget)
            })
        }
        for capture in captures { await capture.value }
    }

    private func captureOne(_ request: CaptureRequest, _ scWindow: SCWindow,
                            generation sessionGeneration: Int,
                            pixelTarget: CGSize) async {
        guard let image = await captureImage(scWindow, pixelTarget: pixelTarget) else {
            markUnavailable(request.id, generation: sessionGeneration)
            return
        }
        // the ledger is the single authority on what a late result may do:
        // nothing for vanished windows, cache-only for ended sessions
        guard ledger.shouldStore(request.id) else { return }
        cache[request.id] = image
        if ledger.shouldDeliver(request.id, capturedIn: sessionGeneration) {
            onPreview?(request.id, image)
        }
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
                                                    requestGeneration: requestGeneration)
                else { return nil }
                return await self.captureImage(scWindow, pixelTarget: pixelTarget)
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
                              pixelTarget: CGSize) async -> NSImage? {
        let windowSize = scWindow.frame.size
        guard windowSize.width > 1, windowSize.height > 1 else { return nil }
        let configuration = SCStreamConfiguration()
        let fit = min(pixelTarget.width / windowSize.width,
                      pixelTarget.height / windowSize.height, 2)
        configuration.width = max(1, Int(windowSize.width * fit))
        configuration.height = max(1, Int(windowSize.height * fit))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration) else { return nil }
        return NSImage(cgImage: cgImage,
                       size: NSSize(width: CGFloat(cgImage.width) / 2,
                                    height: CGFloat(cgImage.height) / 2))
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

    private func markUnavailable(_ id: AnyHashable, generation sessionGeneration: Int) {
        let status = ScreenRecordingPermission.status
        if !status.isAuthorized {
            onPermissionRequired?(status)
            return
        }
        guard cache[id] == nil,
              ledger.shouldDeliver(id, capturedIn: sessionGeneration) else { return }
        onPreviewUnavailable?(id)
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
