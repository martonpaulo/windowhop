import AppKit
import ApplicationServices
import WindowHopKit

/// AXUIElement helpers, ported from AltTab v10.12.0's api-wrappers/AXUIElement.swift
/// minus the private SPI (_AXUIElementGetWindow, _AXUIElementCreateWithRemoteToken).
/// Window identity is the AXUIElement itself (CFEqual/CFHash), which is stable per process.
public enum AXError: Error {
    case runtimeError
}

/// Not in the public headers, but a plain attribute string served by AppKit windows
/// through the public AX API — attribute names are app-defined strings by design.
let kAXFullscreenAttribute = "AXFullScreen"

/// AX element references cross from the AX events thread to the AX reads queue and
/// on to main as window identities (they are compared and hashed there, never read).
///
/// `@unchecked Sendable` invariant: an AXUIElement is an immutable CF reference to a
/// remote accessibility object. Retaining, releasing, hashing and comparing it is
/// thread-safe (atomic CF reference counting, CFEqual/CFHash over immutable pid and
/// token), and every call that talks to the target app goes through the AX reads or
/// actions queues, never main. The SDK does not annotate the type, so this one
/// conformance stands in for it.
extension AXUIElement: @retroactive @unchecked Sendable {}

/// Batched attribute values for one AX call.
public struct AXAttributes: Sendable {
    public var title: String?
    public var role: String?
    public var subrole: String?
    public var isMinimized: Bool?
    public var isFullscreen: Bool?
    public var document: String?
    public var children: [AXUIElement]?
    public var focusedWindow: AXUIElement?
    public var closeButton: AXUIElement?
    public var minimizeButton: AXUIElement?
    public var zoomButton: AXUIElement?
    /// The title-bar buttons' kAXEnabled, read separately on window creation
    /// (see AXNotificationRouter); nil when this read did not include them.
    public var titleBarButtons: PictureInPictureDetector.TitleBarButtons?
    public var windows: [AXUIElement]?
    public var position: CGPoint?
    public var size: CGSize?
    /// The AX error each requested key answered with instead of a value.
    public var errors: [String: ApplicationServices.AXError] = [:]

    /// Whether `key`'s read failed. `.noValue` and `.attributeUnsupported` are
    /// legitimate absence, not failure.
    public func readFailed(_ key: String) -> Bool {
        guard let error = errors[key] else { return false }
        return error != .noValue && error != .attributeUnsupported
    }

    /// `value` (the field read for `key`) as a value, a legitimate absence, or a failure.
    public func read<Value>(_ key: String, _ value: Value?) -> AttributeRead<Value> {
        if let value { return .value(value) }
        return readFailed(key) ? .failed : .absent
    }
}

extension AXUIElement {
    /// Default AX timeout is 6s; reduce it so unresponsive apps can't pile up blocked calls.
    public static func setGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    }

    private func throwIfNotSuccess(_ result: ApplicationServices.AXError) throws {
        // .cannotComplete means the app is unresponsive or mid-launch: worth retrying.
        // Other non-success codes are permanent for this element; callers treat them as absence.
        if result == .cannotComplete {
            throw AXError.runtimeError
        }
    }

    /// Returns false when the notification can never be delivered, true on success,
    /// and throws when the app was unresponsive and a retry may succeed.
    @discardableResult
    func subscribe(_ observer: AXObserver, _ notification: String,
                   refcon: UnsafeMutableRawPointer) throws -> Bool {
        let result = AXObserverAddNotification(observer, self, notification as CFString, refcon)
        if result == .success || result == .notificationAlreadyRegistered {
            return true
        }
        if result == .notificationUnsupported || result == .notImplemented {
            return false
        }
        throw AXError.runtimeError
    }

    public func attributes(_ keys: [String]) throws -> AXAttributes {
        var values: CFArray?
        try throwIfNotSuccess(AXUIElementCopyMultipleAttributeValues(self, keys as CFArray, [], &values))
        let array = values as? [CFTypeRef] ?? []
        var result = AXAttributes()
        for (index, key) in keys.enumerated() {
            guard index < array.count else {
                // no answer at all for this key (the whole call failed)
                result.errors[key] = .failure
                continue
            }
            let value = array[index]
            if let error = axErrorCode(value) {
                result.errors[key] = error
                continue
            }
            switch key {
            case kAXTitleAttribute: result.title = castSafely(value)
            case kAXRoleAttribute: result.role = castSafely(value)
            case kAXSubroleAttribute: result.subrole = castSafely(value)
            case kAXMinimizedAttribute: result.isMinimized = castSafely(value)
            case kAXFullscreenAttribute: result.isFullscreen = castSafely(value)
            case kAXDocumentAttribute: result.document = castSafely(value)
            case kAXChildrenAttribute: result.children = castSafely(value)
            case kAXFocusedWindowAttribute: result.focusedWindow = castSafely(value)
            case kAXCloseButtonAttribute: result.closeButton = castSafely(value)
            case kAXMinimizeButtonAttribute: result.minimizeButton = castSafely(value)
            case kAXZoomButtonAttribute: result.zoomButton = castSafely(value)
            case kAXWindowsAttribute: result.windows = castSafely(value)
            case kAXPositionAttribute: result.position = castSafely(value)
            case kAXSizeAttribute: result.size = castSafely(value)
            default: break
            }
        }
        return result
    }

    /// AXUIElementCopyMultipleAttributeValues without .stopOnError returns placeholder
    /// AXValues of type .axError for attributes it could not read; this is their code.
    private func axErrorCode(_ value: CFTypeRef) -> ApplicationServices.AXError? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .axError else { return nil }
        var code = ApplicationServices.AXError.failure.rawValue
        guard AXValueGetValue(axValue, .axError, &code) else { return .failure }
        return ApplicationServices.AXError(rawValue: code) ?? .failure
    }

    /// Placeholder .axError values map to nil (their code is recorded separately).
    private func castSafely<T>(_ value: CFTypeRef) -> T? {
        switch CFGetTypeID(value) {
        case AXValueGetTypeID():
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .axError:
                return nil
            case .cgSize:
                var size = CGSize.zero
                AXValueGetValue(axValue, .cgSize, &size)
                return size as? T
            case .cgPoint:
                var point = CGPoint.zero
                AXValueGetValue(axValue, .cgPoint, &point)
                return point as? T
            default:
                return nil
            }
        default:
            return value as? T
        }
    }

    /// The app's window list. Public AX only: windows on other Spaces are not returned
    /// until visited; the store compensates by re-enumerating on Space changes and by
    /// keeping already-discovered elements alive.
    ///
    /// A single-attribute read is used so the AX error code survives: a timeout must stay
    /// distinguishable from an app that successfully lists zero windows.
    public func windowElements() -> WindowEnumeration<AXUIElement> {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value)
        return Self.windowEnumeration(result: result, value: value)
    }

    /// Maps a `kAXWindows` read to its enumeration outcome. `.noValue` and
    /// `.attributeUnsupported` are answers (no windows); `.invalidUIElement` means the
    /// app element is dead; every other error is a failed read.
    static func windowEnumeration(result: ApplicationServices.AXError,
                                  value: CFTypeRef?) -> WindowEnumeration<AXUIElement> {
        switch result {
        case .success:
            guard let windows = value as? [AXUIElement] else { return .unavailable }
            // macOS sometimes returns duplicate entries (e.g. Mail starting at login)
            return .listed(Set(windows))
        case .noValue, .attributeUnsupported:
            return .listed([])
        case .invalidUIElement:
            return .applicationInvalid
        default:
            return .unavailable
        }
    }

    /// Detects dead elements: a window that was destroyed while its
    /// kAXUIElementDestroyed notification was missed answers .invalidUIElement
    /// to any attribute read. Busy apps answer .cannotComplete and count as
    /// alive. Concept ported from AltTab's missing-window checks on trigger
    /// (upstream 39070383); without CGWindowIDs this is the public-API version.
    public func isStillValid() -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, kAXRoleAttribute as CFString, &value)
        return result != .invalidUIElement
    }

    public func setAttribute(_ key: String, _ value: Any) throws {
        try throwIfNotSuccess(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef))
    }

    public func performAction(_ action: String) throws {
        try throwIfNotSuccess(AXUIElementPerformAction(self, action as CFString))
    }

    /// OS-level tab bar of a window, from its AXTabGroup child (Finder, Terminal,
    /// Safari, …): one title per AXTabButton, never guessed, never parsed from the
    /// window title. Only the group's visible tab exposes this. `window` holds the
    /// window's batched attributes including kAXChildren. This gathers AX facts
    /// only; `TabObservation.classify` decides what they establish.
    public static func tabObservation(fromWindow window: AXAttributes) -> TabObservation {
        let children = window.read(kAXChildrenAttribute, window.children)
        return TabObservation.classify(children: children.map(childFacts))
    }

    /// Reads children until the first AXTabGroup, which is the one that decides.
    private static func childFacts(_ children: [AXUIElement]) -> [TabObservation.ChildFacts] {
        var facts = [TabObservation.ChildFacts]()
        for child in children {
            // a thrown read means the app did not answer: that is a failure, not "not a tab"
            guard let attributes = try? child.attributes([kAXRoleAttribute, kAXChildrenAttribute]) else {
                facts.append(TabObservation.ChildFacts(role: .failed, tabs: .failed))
                continue
            }
            let role = attributes.read(kAXRoleAttribute, attributes.role)
            guard case .value("AXTabGroup") = role else {
                facts.append(TabObservation.ChildFacts(role: role, tabs: .absent))
                continue
            }
            let tabs = attributes.read(kAXChildrenAttribute, attributes.children).map { tabs in
                tabs.map(tabButtonFacts)
            }
            facts.append(TabObservation.ChildFacts(role: role, tabs: tabs))
            break
        }
        return facts
    }

    private static func tabButtonFacts(_ tab: AXUIElement) -> TabObservation.TabButtonFacts {
        guard let attributes = try? tab.attributes([kAXSubroleAttribute, kAXTitleAttribute]) else {
            return TabObservation.TabButtonFacts(subrole: .failed, title: .failed)
        }
        return TabObservation.TabButtonFacts(
            subrole: attributes.read(kAXSubroleAttribute, attributes.subrole),
            title: attributes.read(kAXTitleAttribute, attributes.title))
    }
}
