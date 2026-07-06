import AppKit
import ScreenCaptureKit

/// Window previews for the optional Window Previews appearance, tuned for an
/// instant-open feel (the AltTab model, public APIs only):
///
/// - The cache lives in memory for the app's lifetime, so opening the switcher
///   shows the last known preview of every window IMMEDIATELY.
/// - Each session then recaptures all visible windows in parallel; a fresh
///   snapshot replaces the stale one live (the tile crossfades unless Reduce
///   Motion is on). Nothing is captured while the switcher is closed.
/// - Images are requested already scaled to tile size (no full-resolution
///   retention), never written to disk, never transmitted, and evicted the
///   moment their window disappears.
/// - Public ScreenCaptureKit only. AX windows are matched to SCWindows by
///   pid + frame (+ title), and every request receives a DISTINCT window —
///   two windows of the same app can never share a preview. When no confident
///   match exists the tile keeps its icon fallback; a wrong preview is worse
///   than none.
public final class PreviewProvider {
    public static let shared = PreviewProvider()

    /// Delivered on the main thread as fresh captures arrive for the current session.
    public var onPreview: ((AnyHashable, NSImage) -> Void)?

    private var generation = 0
    private var cache: [AnyHashable: NSImage] = [:]

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

    public func evict(_ id: AnyHashable) {
        cache[id] = nil
    }

    /// Used when the user switches back to App Icons: nothing to retain.
    public func evictAll() {
        cache.removeAll()
    }

    // MARK: - Session lifecycle

    /// Starts recapturing previews for the session's items. No-op unless Window
    /// Previews mode is active and Screen Recording is granted.
    public func beginSession(items: [SwitcherItem], targetSize: CGSize, scale: CGFloat) {
        guard Preferences.shared.appearanceMode == .windowPreviews,
              ScreenRecordingPermission.isGranted else { return }
        generation += 1
        let sessionGeneration = generation
        let requests: [CaptureRequest] = items.compactMap { item in
            guard let window = item.window, let app = window.app else { return nil }
            return CaptureRequest(id: item.id, pid: app.pid,
                                  title: item.title, frame: window.frame)
        }
        let pixelTarget = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        Task { [weak self] in
            await self?.capture(requests, generation: sessionGeneration, pixelTarget: pixelTarget)
        }
    }

    /// Stops live delivery; the cache stays warm for an instant next open.
    /// In-flight captures may still finish into the cache (free freshness),
    /// but no further capture work starts while the switcher is closed.
    public func endSession() {
        generation += 1
    }

    // MARK: - Capture

    private func capture(_ requests: [CaptureRequest], generation sessionGeneration: Int,
                         pixelTarget: CGSize) async {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
        let candidates = content.windows.enumerated().map { index, window in
            MatchCandidate(index: index,
                           pid: window.owningApplication?.processID ?? -1,
                           title: window.title ?? "",
                           frame: window.frame)
        }
        let assignments = PreviewProvider.assign(
            requests: requests.map {
                MatchRequest(id: $0.id, pid: $0.pid, title: $0.title, frame: $0.frame)
            },
            candidates: candidates)
        // parallel capture in small waves: fast without saturating WindowServer
        let assigned = requests.compactMap { request in
            assignments[request.id].map { (request, content.windows[$0]) }
        }
        for wave in stride(from: 0, to: assigned.count, by: 4).map({ Array(assigned[$0..<min($0 + 4, assigned.count)]) }) {
            let stale = await MainActor.run { self.generation != sessionGeneration }
            await withTaskGroup(of: Void.self) { group in
                for (request, scWindow) in wave {
                    group.addTask { [weak self] in
                        await self?.captureOne(request, scWindow, generation: sessionGeneration,
                                               pixelTarget: pixelTarget, deliver: !stale)
                    }
                }
            }
            // once the session ended, finish the current wave into the cache but
            // start no further capture work
            if stale { return }
        }
    }

    private func captureOne(_ request: CaptureRequest, _ scWindow: SCWindow,
                            generation sessionGeneration: Int,
                            pixelTarget: CGSize, deliver: Bool) async {
        let windowSize = scWindow.frame.size
        guard windowSize.width > 1, windowSize.height > 1 else { return }
        let configuration = SCStreamConfiguration()
        // ask ScreenCaptureKit for a tile-sized image directly: the full-
        // resolution window content is never held by WindowHop
        let fit = min(pixelTarget.width / windowSize.width,
                      pixelTarget.height / windowSize.height, 2)
        configuration.width = max(1, Int(windowSize.width * fit))
        configuration.height = max(1, Int(windowSize.height * fit))
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration) else { return }
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: CGFloat(cgImage.width) / 2,
                                         height: CGFloat(cgImage.height) / 2))
        await MainActor.run {
            self.cache[request.id] = image
            if deliver, self.generation == sessionGeneration {
                self.onPreview?(request.id, image)
            }
        }
    }

    // MARK: - Matching (pure, unit-tested)

    struct MatchRequest {
        let id: AnyHashable
        let pid: pid_t
        let title: String
        let frame: CGRect?
    }

    struct MatchCandidate {
        let index: Int
        let pid: pid_t
        let title: String
        let frame: CGRect
    }

    /// Unique assignment of SCWindows to requests: frame proximity first (title
    /// breaks ties), then exact title. Every candidate is consumed at most once,
    /// so two same-app windows can never receive the same preview. Requests with
    /// no confident match stay unassigned (icon fallback) — never guessed.
    static func assign(requests: [MatchRequest],
                       candidates: [MatchCandidate]) -> [AnyHashable: Int] {
        var available = Set(candidates.map { $0.index })
        var result = [AnyHashable: Int]()
        func frameClose(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.origin.x - b.origin.x) < 5 && abs(a.origin.y - b.origin.y) < 5
                && abs(a.width - b.width) < 5 && abs(a.height - b.height) < 5
        }
        // pass 1: frame match, preferring an equal title among frame-close candidates
        for request in requests {
            guard let frame = request.frame else { continue }
            let frameMatches = candidates.filter {
                available.contains($0.index) && $0.pid == request.pid && frameClose($0.frame, frame)
            }
            guard !frameMatches.isEmpty else { continue }
            let chosen = frameMatches.first { $0.title == request.title } ?? frameMatches[0]
            result[request.id] = chosen.index
            available.remove(chosen.index)
        }
        // pass 2: exact title for whatever is left
        for request in requests where result[request.id] == nil {
            guard let chosen = candidates.first(where: {
                available.contains($0.index) && $0.pid == request.pid && $0.title == request.title
            }) else { continue }
            result[request.id] = chosen.index
            available.remove(chosen.index)
        }
        return result
    }
}
