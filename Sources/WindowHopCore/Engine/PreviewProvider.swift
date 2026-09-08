import AppKit
import ScreenCaptureKit

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
    private var activeSessionGeneration: Int?
    private var expandedGeneration = 0

    struct CaptureRequest {
        let id: AnyHashable
        let pid: pid_t
        let title: String
        let frame: CGRect?
    }

    /// Stable IDs are immutable value identities in WindowHop, but
    /// `AnyHashable` predates Sendable conformance. This wrapper limits the
    /// unchecked boundary to transport into the main-actor delivery closure.
    private struct SendableIdentity: @unchecked Sendable {
        let value: AnyHashable
    }

    private init() {}

    // MARK: - Cache (memory-only, app lifetime, evicted with the window)

    public func cachedPreview(for id: AnyHashable) -> NSImage? {
        cache[id]
    }

    public func evict(_ id: AnyHashable) {
        cache[id] = nil
        ledger.evict(id)
    }

    /// Used when the user switches back to App Icons: nothing to retain.
    public func evictAll() {
        cache.removeAll()
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
        ledger.endSession()
    }

    /// Requests a larger snapshot for the dwell presentation. It remains fully
    /// session-scoped and only delivers when both the session and target
    /// generation are still current.
    public func requestExpandedPreview(item: SwitcherItem,
                                       targetSize: CGSize,
                                       scale: CGFloat) {
        guard Preferences.shared.appearanceMode == .windowPreviews,
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

    // MARK: - Capture

    private func capture(_ requests: [CaptureRequest], generation sessionGeneration: Int,
                         pixelTarget: CGSize) async {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            for request in requests {
                await markUnavailable(request.id, generation: sessionGeneration)
            }
            return
        }
        let assignments = PreviewMatcher.assign(
            requests: requests.map(Self.matchRequest),
            candidates: Self.matchCandidates(in: content.windows))
        // parallel capture in small waves: fast without saturating WindowServer
        let assigned = requests.compactMap { request in
            assignments[request.id].map { (request, content.windows[$0]) }
        }
        let assignedIDs = Set(assigned.map { $0.0.id })
        for request in requests where !assignedIDs.contains(request.id) {
            await markUnavailable(request.id, generation: sessionGeneration)
        }
        for wave in stride(from: 0, to: assigned.count, by: 4).map({ Array(assigned[$0..<min($0 + 4, assigned.count)]) }) {
            let staleBeforeWave = await MainActor.run {
                self.ledger.generation != sessionGeneration
            }
            if staleBeforeWave { return }
            await withTaskGroup(of: Void.self) { group in
                for (request, scWindow) in wave {
                    group.addTask { [weak self] in
                        await self?.captureOne(request, scWindow, generation: sessionGeneration,
                                               pixelTarget: pixelTarget)
                    }
                }
            }
            // once the session ended, finish the current wave into the cache but
            // start no further capture work
            let staleAfterWave = await MainActor.run {
                self.ledger.generation != sessionGeneration
            }
            if staleAfterWave { return }
        }
    }

    private func captureOne(_ request: CaptureRequest, _ scWindow: SCWindow,
                            generation sessionGeneration: Int,
                            pixelTarget: CGSize) async {
        guard let image = await captureImage(scWindow, pixelTarget: pixelTarget) else {
            await markUnavailable(request.id, generation: sessionGeneration)
            return
        }
        await MainActor.run {
            // the ledger is the single authority on what a late result may do:
            // nothing for vanished windows, cache-only for ended sessions
            guard self.ledger.shouldStore(request.id) else { return }
            self.cache[request.id] = image
            if self.ledger.shouldDeliver(request.id, capturedIn: sessionGeneration) {
                self.onPreview?(request.id, image)
            }
        }
    }

    private func captureExpanded(_ request: CaptureRequest,
                                 sessionGeneration: Int,
                                 requestGeneration: Int,
                                 pixelTarget: CGSize) async {
        let identity = SendableIdentity(value: request.id)
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
                self.isExpandedRequestCurrent(identity.value,
                                              sessionGeneration: sessionGeneration,
                                              requestGeneration: requestGeneration)
            },
            capture: { await self.captureImage($0, pixelTarget: pixelTarget) },
            deliver: { image in
                self.cache[identity.value] = image
                self.onPreview?(identity.value, image)
                self.onExpandedPreview?(identity.value, image)
            })
    }

    /// True while this expanded request may still spend capture work and
    /// deliver: same session, same request, and a target the ledger still owns.
    @MainActor
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

    private func markUnavailable(_ id: AnyHashable, generation sessionGeneration: Int) async {
        let identity = SendableIdentity(value: id)
        await MainActor.run {
            let status = ScreenRecordingPermission.status
            if !status.isAuthorized {
                self.onPermissionRequired?(status)
                return
            }
            guard self.cache[identity.value] == nil,
                  self.ledger.shouldDeliver(identity.value,
                                            capturedIn: sessionGeneration) else { return }
            self.onPreviewUnavailable?(identity.value)
        }
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
                await MainActor.run { completion(["dump-previews: no shareable content"]) }
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
            await MainActor.run { completion(lines) }
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
