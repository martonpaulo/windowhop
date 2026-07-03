import AppKit
import ScreenCaptureKit

/// Session-scoped window previews for the optional Window Previews appearance.
///
/// Design constraints (see docs/architecture.md):
/// - Captures happen only while a switcher session is open — never while idle.
/// - Images are requested already scaled to tile size (no full-resolution
///   retention), kept only in memory, cleared when the session ends, and never
///   written to disk or transmitted.
/// - Capture is asynchronous and never blocks panel presentation or input; a
///   missing preview simply leaves the app-icon fallback in place.
/// - Public ScreenCaptureKit only. AX windows are matched to SCWindows by
///   process id + frame (+ title as tiebreaker) because public AX exposes no
///   CGWindowID bridge; an unmatched window keeps its icon fallback.
public final class PreviewProvider {
    public static let shared = PreviewProvider()

    /// Delivered on the main thread as previews arrive for the current session.
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

    /// The preview already captured this session, if any (main thread).
    public func cachedPreview(for id: AnyHashable) -> NSImage? {
        cache[id]
    }

    /// Starts capturing previews for the session's items. No-op unless Window
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

    /// Ends the session: stale captures are dropped on arrival and the memory
    /// cache is released immediately.
    public func endSession() {
        generation += 1
        cache.removeAll()
    }

    // MARK: - Capture

    private func capture(_ requests: [CaptureRequest], generation sessionGeneration: Int,
                         pixelTarget: CGSize) async {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
        for request in requests {
            // a newer session (or none) makes the remaining work stale
            let stale = await MainActor.run { self.generation != sessionGeneration }
            if stale { return }
            guard let scWindow = match(request, in: content.windows) else { continue }
            let configuration = SCStreamConfiguration()
            let windowSize = scWindow.frame.size
            guard windowSize.width > 1, windowSize.height > 1 else { continue }
            // ask ScreenCaptureKit for a tile-sized image directly: the full-
            // resolution window content is never held by WindowHop
            let fit = min(pixelTarget.width / windowSize.width,
                          pixelTarget.height / windowSize.height, 2)
            configuration.width = max(1, Int(windowSize.width * fit))
            configuration.height = max(1, Int(windowSize.height * fit))
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            guard let cgImage = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration) else { continue }
            let image = NSImage(cgImage: cgImage,
                                size: NSSize(width: CGFloat(cgImage.width) / 2,
                                             height: CGFloat(cgImage.height) / 2))
            await MainActor.run {
                guard self.generation == sessionGeneration else { return }
                self.cache[request.id] = image
                self.onPreview?(request.id, image)
            }
        }
    }

    /// pid + frame proximity, then title. Public AX has no CGWindowID bridge, so
    /// this heuristic is the honest option; failure means icon fallback, never a
    /// missing or broken entry.
    func match(_ request: CaptureRequest, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { $0.owningApplication?.processID == request.pid }
        if let frame = request.frame {
            let byFrame = candidates.filter { window in
                abs(window.frame.origin.x - frame.origin.x) < 4
                    && abs(window.frame.origin.y - frame.origin.y) < 4
                    && abs(window.frame.width - frame.width) < 4
                    && abs(window.frame.height - frame.height) < 4
            }
            if byFrame.count == 1 { return byFrame.first }
            if byFrame.count > 1 {
                return byFrame.first { $0.title == request.title } ?? byFrame.first
            }
        }
        return candidates.first { $0.title == request.title }
    }
}
