import AppKit
import ApplicationServices

/// One real window we track. For other apps' windows the identity is the
/// AXUIElement itself (CFEqual-stable for the lifetime of the owning process), so
/// duplicate titles can never collide. WindowHop's own Settings window is the one
/// deliberate exception to the own-process exclusion: it is backed directly by its
/// NSWindow instead of AX, keeping every other internal surface out by construction.
public final class TrackedWindow {
    /// Stable identity for snapshots, tab groups, and the preview cache.
    /// ObjectIdentifier is deliberately NOT used: the runtime reuses object
    /// addresses, which once let a dead window's cached preview leak onto a
    /// newly created one.
    public let stableId = UUID()
    public let ax: AXUIElement?
    public let app: TrackedApp?
    public private(set) weak var nativeWindow: NSWindow?
    /// True only for the registered WindowHop Settings window entry.
    public let isOwnSettingsEntry: Bool
    public private(set) var title: String
    /// The raw AXDocument value, kept for CollisionLabel; nil for the Settings entry.
    public private(set) var documentPath: String?
    /// Titles of this window's last complete tab bar read; nil when it showed none.
    /// Derived AX cache, never persisted.
    public private(set) var reportedTabTitles: [String]?
    public var tabCount: Int? { reportedTabTitles?.count }
    public internal(set) var isMinimized: Bool
    public internal(set) var isFullscreen: Bool
    public internal(set) var isOnCurrentSpace = true
    public internal(set) var frame: CGRect?
    /// Result of WindowEligibility.isActualWindow at the latest attribute refresh.
    public internal(set) var isActual: Bool
    /// True when this window is really an inactive tab of a native tab group;
    /// tabbed windows are never shown as switcher entries (see TabGroupResolver).
    public internal(set) var isTabbed = false
    /// Whether the window server keeps this window floating (Picture in
    /// Picture); nil until resolved once at snapshot time. PiP-ness is
    /// intrinsic to a window, so one resolution is enough.
    public internal(set) var isPictureInPicture: Bool?
    /// The AX close button's enabled state, read once per window creation (nil
    /// when the window has none or it was never read). Evidence for
    /// PictureInPictureDetector; a floating window keeps it for its lifetime.
    public private(set) var closeButtonEnabled: Bool?
    /// Identities of this window's tab group members (including itself), when known.
    public internal(set) var tabGroupIds: [UUID]?

    init(ax: AXUIElement, app: TrackedApp, attributes: AXAttributes, tabs: TabObservation) {
        self.ax = ax
        self.app = app
        nativeWindow = nil
        isOwnSettingsEntry = false
        documentPath = attributes.document
        title = TitleResolver.resolve(axTitle: attributes.title,
                                      documentPath: attributes.document,
                                      appName: app.name)
        if case .group(let titles) = tabs {
            reportedTabTitles = titles
        }
        isMinimized = attributes.isMinimized ?? false
        isFullscreen = attributes.isFullscreen ?? false
        frame = TrackedWindow.frame(from: attributes)
        isActual = WindowEligibility.isActualWindow(app.windowFacts(from: attributes))
        closeButtonEnabled = attributes.closeButtonEnabled
    }

    /// The own-Settings-window exception: a native entry with the WindowHop icon.
    /// The entry title is fixed — the window's visible title follows the selected
    /// settings pane, which would make a confusing switcher label.
    init(settingsWindow: NSWindow) {
        ax = nil
        app = nil
        nativeWindow = settingsWindow
        isOwnSettingsEntry = true
        title = SettingsWindowController.switcherEntryTitle
        isMinimized = settingsWindow.isMiniaturized
        isFullscreen = false
        frame = settingsWindow.frame
        isActual = true
    }

    func update(from attributes: AXAttributes, tabs: TabObservation) {
        guard let app else { return }
        documentPath = attributes.document
        title = TitleResolver.resolve(axTitle: attributes.title,
                                      documentPath: attributes.document,
                                      appName: app.name)
        switch tabs {
        case .group(let titles): reportedTabTitles = titles
        case .standalone: reportedTabTitles = nil
        case .unknown: break // an incomplete read keeps the last complete tab bar
        }
        isMinimized = attributes.isMinimized ?? false
        isFullscreen = attributes.isFullscreen ?? false
        frame = TrackedWindow.frame(from: attributes)
        isActual = WindowEligibility.isActualWindow(app.windowFacts(from: attributes))
        // only creation events carry the close button; a new answer re-opens the PiP verdict
        if let enabled = attributes.closeButtonEnabled, enabled != closeButtonEnabled {
            closeButtonEnabled = enabled
            isPictureInPicture = nil
        }
    }

    /// Display values for the switcher entry.
    public var appName: String {
        isOwnSettingsEntry ? "WindowHop" : (app?.name ?? "")
    }

    public var appIcon: NSImage? {
        isOwnSettingsEntry ? NSApp.applicationIconImage : app?.icon
    }

    private static func frame(from attributes: AXAttributes) -> CGRect? {
        guard let position = attributes.position, let size = attributes.size else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Window frames from AX use Quartz coordinates (top-left origin of the primary
    /// display); NSScreen frames use Cocoa coordinates (bottom-left). Ported from
    /// AltTab's Window.isOnScreen.
    ///
    /// The registered Settings window is the one entry backed by a live NSWindow.
    /// Its frame is already Cocoa and changes whenever the user drags it, so it
    /// is read live and compared without conversion; the stored frame captured
    /// at registration would answer for the display it opened on forever.
    public func isOn(screen: NSScreen) -> Bool {
        if let nativeWindow {
            return nativeWindow.frame.intersects(screen.frame)
        }
        guard let frame, let primary = NSScreen.screens.first else { return true }
        return frame.intersects(TrackedWindow.quartzFrame(of: screen, primary: primary))
    }

    /// A screen's frame in the Quartz coordinates AX reports windows in.
    static func quartzFrame(of screen: NSScreen, primary: NSScreen) -> CGRect {
        var quartz = screen.frame
        quartz.origin.y = primary.frame.maxY - screen.frame.maxY
        return quartz
    }
}
