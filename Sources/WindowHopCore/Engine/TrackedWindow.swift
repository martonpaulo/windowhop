import AppKit
import ApplicationServices

/// One real window we track. Identity is the AXUIElement itself (CFEqual-stable
/// for the lifetime of the process that owns the window), so duplicate titles
/// can never collide.
public final class TrackedWindow {
    public let ax: AXUIElement
    public unowned let app: TrackedApp
    public private(set) var title: String
    public private(set) var tabCount: Int?
    public internal(set) var isMinimized: Bool
    public internal(set) var isFullscreen: Bool
    public internal(set) var isOnCurrentSpace = true
    public internal(set) var frame: CGRect?
    /// Result of WindowEligibility.isActualWindow at the latest attribute refresh.
    public internal(set) var isActual: Bool

    init(ax: AXUIElement, app: TrackedApp, attributes: AXAttributes, tabCount: Int?) {
        self.ax = ax
        self.app = app
        title = TitleResolver.resolve(axTitle: attributes.title,
                                      documentPath: attributes.document,
                                      appName: app.name)
        self.tabCount = tabCount
        isMinimized = attributes.isMinimized ?? false
        isFullscreen = attributes.isFullscreen ?? false
        frame = TrackedWindow.frame(from: attributes)
        isActual = WindowEligibility.isActualWindow(app.windowFacts(from: attributes))
    }

    func update(from attributes: AXAttributes, tabCount: Int?) {
        title = TitleResolver.resolve(axTitle: attributes.title,
                                      documentPath: attributes.document,
                                      appName: app.name)
        self.tabCount = tabCount
        isMinimized = attributes.isMinimized ?? false
        isFullscreen = attributes.isFullscreen ?? false
        frame = TrackedWindow.frame(from: attributes)
        isActual = WindowEligibility.isActualWindow(app.windowFacts(from: attributes))
    }

    private static func frame(from attributes: AXAttributes) -> CGRect? {
        guard let position = attributes.position, let size = attributes.size else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Window frames from AX use Quartz coordinates (top-left origin of the primary
    /// display); NSScreen frames use Cocoa coordinates (bottom-left). Ported from
    /// AltTab's Window.isOnScreen.
    public func isOn(screen: NSScreen) -> Bool {
        guard let frame, let primary = NSScreen.screens.first else { return true }
        var screenFrameInQuartz = screen.frame
        screenFrameInQuartz.origin.y = primary.frame.maxY - screen.frame.maxY
        return frame.intersects(screenFrameInQuartz)
    }
}
