import AppKit
import ApplicationServices

/// Routes AXObserver notifications to the WindowStore, ported from AltTab v10.12.0's
/// AccessibilityEvents. The observer callback fires on the dedicated AX events thread;
/// attribute reads happen on the AX reads queue; state mutation happens on main.
enum AXNotificationRouter {
    /// Attributes fetched in one batched call whenever a window event arrives.
    static let windowAttributeKeys = [
        kAXTitleAttribute, kAXRoleAttribute, kAXSubroleAttribute, kAXSizeAttribute,
        kAXPositionAttribute, kAXFullscreenAttribute, kAXMinimizedAttribute, kAXDocumentAttribute,
    ]

    static let axObserverCallback: AXObserverCallback = { _, element, notificationName, _ in
        let notification = notificationName as String
        BackgroundWork.axReadsQueue.async {
            route(notification, element)
        }
    }

    /// Runs on the AX reads queue.
    private static func route(_ notification: String, _ element: AXUIElement) {
        var pid = pid_t(0)
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else { return }
        switch notification {
        case kAXApplicationActivatedNotification:
            // some apps focus a window without emitting focusedWindowChanged; treat the
            // activated app's focused window as focused
            let focusedWindow = (try? element.attributes([kAXFocusedWindowAttribute]))?.focusedWindow
            DispatchQueue.main.async {
                WindowStore.shared.appActivated(pid: pid)
            }
            if let focusedWindow {
                routeWindowEvent(kAXFocusedWindowChangedNotification, focusedWindow, pid)
            }
        case kAXApplicationHiddenNotification, kAXApplicationShownNotification:
            let isHidden = notification == kAXApplicationHiddenNotification
            DispatchQueue.main.async {
                WindowStore.shared.appHiddenChanged(pid: pid, isHidden: isHidden)
            }
        case kAXUIElementDestroyedNotification:
            DispatchQueue.main.async {
                WindowStore.shared.removeWindow(element)
            }
        default:
            routeWindowEvent(notification, element, pid)
        }
    }

    /// Reads the window's attributes (and tab group, off the latency-critical path),
    /// then hands plain values to the store. Runs on the AX reads queue.
    static func routeWindowEvent(_ notification: String, _ element: AXUIElement, _ pid: pid_t) {
        // reading our own AX children would call AppKit layout from this thread
        let isOwnProcess = pid == ProcessInfo.processInfo.processIdentifier
        // The close button's enabled state separates Chromium PiP from ordinary floating
        // windows (PictureInPictureDetector). It is fixed for a window's lifetime, so it
        // costs one extra read per window creation, never one per move or resize.
        let isCreation = notification == kAXWindowCreatedNotification
        let keys = windowAttributeKeys + (isOwnProcess ? [] : [kAXChildrenAttribute])
            + (isCreation ? [kAXCloseButtonAttribute] : [])
        guard var read = try? element.attributes(keys) else { return }
        if isCreation, let closeButton = read.closeButton {
            var enabled: CFTypeRef?
            if AXUIElementCopyAttributeValue(closeButton, kAXEnabledAttribute as CFString, &enabled) == .success {
                read.closeButtonEnabled = enabled as? Bool
            }
        }
        let attributes = read
        let tabs = AXUIElement.tabObservation(fromWindow: attributes)
        DispatchQueue.main.async {
            WindowStore.shared.windowEvent(notification, element: element, pid: pid,
                                           attributes: attributes, tabs: tabs)
        }
    }
}
