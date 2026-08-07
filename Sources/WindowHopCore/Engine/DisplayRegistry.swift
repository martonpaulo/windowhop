import AppKit
import Combine
import CoreGraphics

/// The only place that turns real displays into the value types `Core` reasons
/// about. Everything here is read on demand at session start or while Settings
/// is open; nothing is cached and nothing runs while WindowHop is idle.
///
/// Ported from AltTab `src/logic/Screens.swift` (`withMouse()`, `uuid()`) at
/// `317a485b`. See UPSTREAM.md.
public enum DisplayRegistry {
    /// Every connected display with the screen it came from, in system order.
    ///
    /// Descriptors and screens are produced together because resolving a display
    /// UUID is a CoreGraphics round trip, and callers need both.
    public static func connectedDisplays() -> [(descriptor: DisplayDescriptor, screen: NSScreen)] {
        NSScreen.screens.compactMap { screen in
            descriptor(for: screen).map { ($0, screen) }
        }
    }

    public static func availableDisplays() -> [DisplayDescriptor] {
        connectedDisplays().map(\.descriptor)
    }

    /// The display containing the pointer, or nil when it cannot be resolved.
    ///
    /// `NSEvent.mouseLocation` is in Cocoa screen coordinates, the same space as
    /// `NSScreen.frame`, so no conversion is involved.
    ///
    /// This deliberately does not use `NSScreen.main`. Upstream documents that
    /// `NSScreen.main` stopped returning the screen with the key window in macOS
    /// 10.9: with a fullscreen app on the active screen it returns `screens[0]`,
    /// and it does so again when `screensHaveSeparateSpaces` is false and the key
    /// window is not on `screens[0]`.
    /// https://stackoverflow.com/a/56268826/2249756
    public static func pointerDisplayID() -> String? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
        return screen.flatMap(persistentID(for:))
    }

    public static func descriptor(for screen: NSScreen) -> DisplayDescriptor? {
        guard let id = persistentID(for: screen) else { return nil }
        return DisplayDescriptor(id: id,
                                 name: screen.localizedName,
                                 visibleFrame: screen.visibleFrame,
                                 backingScale: screen.backingScaleFactor)
    }

    /// A display identity that survives reconnect, sleep, and reboot.
    ///
    /// `CGDirectDisplayID` is reassigned across reconnects, so persisting one
    /// would silently point a stored choice at a different monitor. The display
    /// UUID is stable and is public CoreGraphics API.
    ///
    /// `CGDisplayCreateUUIDFromDisplayID` and `CFUUIDCreateString` are declared
    /// as implicitly unwrapped but genuinely can return nil, which is why both
    /// are checked here rather than force-unwrapped (upstream rule).
    /// https://developer.apple.com/documentation/coregraphics/1454068-cgdisplaycreateuuidfromdisplayid
    public static func persistentID(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, cfUUID) else { return nil }
        return string as String
    }
}

/// A live list of connected displays for the Settings picker.
///
/// Observation starts when the pane appears and stops when it disappears, so
/// plugging a monitor updates the picker while Settings is open without any work
/// happening once it closes. Event-driven by
/// `didChangeScreenParametersNotification`; nothing is polled.
public final class ConnectedDisplaysModel: ObservableObject {
    @Published public private(set) var displays: [DisplayDescriptor]

    private var observer: NSObjectProtocol?

    public init() {
        displays = DisplayRegistry.availableDisplays()
    }

    deinit { stopObserving() }

    public func startObserving() {
        guard observer == nil else { return }
        displays = DisplayRegistry.availableDisplays()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.displays = DisplayRegistry.availableDisplays()
            }
    }

    public func stopObserving() {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
    }
}
