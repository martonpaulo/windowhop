import AppKit
import ApplicationServices

/// AXUIElement helpers, ported from AltTab v10.12.0's api-wrappers/AXUIElement.swift
/// minus the private SPI (_AXUIElementGetWindow, _AXUIElementCreateWithRemoteToken).
/// Window identity is the AXUIElement itself (CFEqual/CFHash), which is stable per process.
public enum AXError: Error {
    case runtimeError
}

/// Not in the public headers, but a plain attribute string served by AppKit windows
/// through the public AX API — attribute names are app-defined strings by design.
let kAXFullscreenAttribute = "AXFullScreen"

/// Batched attribute values for one AX call.
public struct AXAttributes {
    public var title: String?
    public var role: String?
    public var subrole: String?
    public var isMinimized: Bool?
    public var isFullscreen: Bool?
    public var document: String?
    public var children: [AXUIElement]?
    public var focusedWindow: AXUIElement?
    public var closeButton: AXUIElement?
    public var windows: [AXUIElement]?
    public var position: CGPoint?
    public var size: CGSize?
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
    public func subscribe(_ observer: AXObserver, _ notification: String) throws -> Bool {
        let result = AXObserverAddNotification(observer, self, notification as CFString, nil)
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
            guard index < array.count else { continue }
            let value = array[index]
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
            case kAXWindowsAttribute: result.windows = castSafely(value)
            case kAXPositionAttribute: result.position = castSafely(value)
            case kAXSizeAttribute: result.size = castSafely(value)
            default: break
            }
        }
        return result
    }

    /// AXUIElementCopyMultipleAttributeValues without .stopOnError returns placeholder
    /// AXValues of type .axError for missing attributes; those must map to nil.
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
    public func windowElements() throws -> [AXUIElement] {
        let windows = try attributes([kAXWindowsAttribute]).windows ?? []
        // macOS sometimes returns duplicate entries (e.g. Mail starting at login)
        return Array(Set(windows))
    }

    public func setAttribute(_ key: String, _ value: Any) throws {
        try throwIfNotSuccess(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef))
    }

    public func performAction(_ action: String) throws {
        try throwIfNotSuccess(AXUIElementPerformAction(self, action as CFString))
    }

    /// OS-level tab titles, from the window's AXTabGroup child (Safari, Finder,
    /// Terminal, …). Returns one title per AXTabButton when the window shows a tab
    /// bar with 2 or more tabs, nil otherwise. Never guessed, never parsed from the
    /// window title. Only the group's visible tab exposes this.
    public static func tabTitles(fromWindowChildren children: [AXUIElement]?) -> [String]? {
        guard let children else { return nil }
        for child in children {
            let attributes = try? child.attributes([kAXRoleAttribute, kAXChildrenAttribute])
            guard attributes?.role == "AXTabGroup", let tabChildren = attributes?.children else { continue }
            let titles = tabChildren.compactMap { tab -> String? in
                let tabAttributes = try? tab.attributes([kAXSubroleAttribute, kAXTitleAttribute])
                guard tabAttributes?.subrole == "AXTabButton" else { return nil }
                return tabAttributes?.title ?? ""
            }
            return titles.count >= 2 ? titles : nil
        }
        return nil
    }
}
