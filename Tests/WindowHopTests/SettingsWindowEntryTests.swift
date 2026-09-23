import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// The own-Settings-window exception: it appears exactly once while open,
    /// participates in MRU, hides while minimized, and disappears on close.
    /// Uses a fresh WindowStore instance and drives NSWindow
    /// lifecycle via the notifications the store observes.
    @MainActor
    final class SettingsWindowEntryTests {
        private var isolated: IsolatedPreferences!
        private var store: WindowStore!
        private var window: NSWindow!

        init() throws {
            isolated = try IsolatedPreferences()
            store = WindowStore(preferences: isolated.preferences, previews: isolated.previews)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.title = "WindowHop Settings"
        }

        isolated deinit {
            window = nil
            store = nil
            isolated.remove()
            isolated = nil
        }

        @Test func registeredSettingsWindowAppearsExactlyOnce() {
            store.registerOwnWindow(window)
            let items = store.snapshot()
            #expect(items.count == 1)
            #expect(items[0].title == "WindowHop Settings")
            #expect(items[0].appName == "WindowHop")
        }

        @Test func doubleRegistrationDoesNotDuplicate() {
            store.registerOwnWindow(window)
            store.registerOwnWindow(window)
            #expect(store.snapshot().count == 1)
        }

        @Test func closingRemovesTheEntry() {
            store.registerOwnWindow(window)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            #expect(store.snapshot().count == 0)
        }

        @Test func minimizedSettingsWindowIsExcluded() {
            store.registerOwnWindow(window)
            // headless tests can't really miniaturize; the store derives the state from
            // the notification name, which is what the Dock delivers in real usage
            NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
            #expect(store.snapshot().count == 0)
            NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
            #expect(store.snapshot().count == 1)
        }

        @Test func becomingKeyMovesEntryToMRUFront() {
            store.registerOwnWindow(window)
            #expect(store.windows.first?.isOwnSettingsEntry == true)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            #expect(store.windows.first?.isOwnSettingsEntry == true)
        }

        // MARK: - MRU ordering through the store (issue #58)

        /// The registered entries are the only store path tests can drive without AX;
        /// they exercise the same MRUOrder owner that orders AX windows.
        private func makeWindow(_ title: String) -> NSWindow {
            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: true)
            other.isReleasedWhenClosed = false
            other.title = title
            return other
        }

        private var nativeOrder: [NSWindow?] { store.windows.map(\.nativeWindow) }

        @Test func secondRegisteredWindowEntersAtFront() {
            let second = makeWindow("Second")
            store.registerOwnWindow(window)
            store.registerOwnWindow(second)
            #expect(nativeOrder == [second, window])
        }

        @Test func becomingKeyReordersAmongOwnEntries() {
            let second = makeWindow("Second")
            store.registerOwnWindow(window)
            store.registerOwnWindow(second)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            #expect(nativeOrder == [window, second])
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            #expect(nativeOrder == [window, second], "focusing the front entry is a no-op")
        }

        @Test func closingOneEntryKeepsTheOthersOrder() {
            let second = makeWindow("Second")
            let third = makeWindow("Third")
            store.registerOwnWindow(window)
            store.registerOwnWindow(second)
            store.registerOwnWindow(third)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: second)
            #expect(nativeOrder == [third, window])
        }

        @Test func otherOwnWindowsRemainExcludedByTheDisplayRule() {
            // panels, alerts, onboarding: own windows that are NOT the settings exception
            let ownWindow = WindowDisplayState(
                isMinimized: false, isAppHidden: false,
                isOwnWindow: true, isOwnSettingsWindow: false,
                isOnCurrentSpace: true, isOnActiveDisplay: true)
            #expect(!WindowEligibility.shouldDisplay(ownWindow, policy: .init()))
            let settingsWindow = WindowDisplayState(
                isMinimized: false, isAppHidden: false,
                isOwnWindow: true, isOwnSettingsWindow: true,
                isOnCurrentSpace: true, isOnActiveDisplay: true)
            #expect(WindowEligibility.shouldDisplay(settingsWindow, policy: .init()))
        }

        @Test func nativeEntryActivationAndCloseUseAppKitPaths() {
            store.registerOwnWindow(window)
            let entry = store.windows[0]
            #expect(entry.ax == nil)
            #expect(entry.app == nil)
            #expect(entry.nativeWindow != nil)
        }

        // MARK: - Live display membership (issue #22)

        /// The entry stored the frame it was registered with, so moving Settings to
        /// another display left it filed under the display it opened on.
        @Test func movingTheWindowUpdatesItsDisplayMembership() throws {
            let screen = try #require(NSScreen.screens.first)
            window.setFrame(
                NSRect(
                    x: screen.frame.midX, y: screen.frame.midY,
                    width: 400, height: 300), display: false)
            store.registerOwnWindow(window)
            let entry = try #require(store.windows.first)
            #expect(entry.isOn(screen: screen))

            window.setFrame(
                NSRect(
                    x: screen.frame.maxX + 2000, y: screen.frame.midY,
                    width: 400, height: 300), display: false)

            #expect(
                !entry.isOn(screen: screen),
                "the entry must follow the window's live location")
        }

        @Test func resizingBackOntoTheScreenRestoresMembership() throws {
            let screen = try #require(NSScreen.screens.first)
            window.setFrame(
                NSRect(
                    x: screen.frame.maxX + 2000, y: screen.frame.midY,
                    width: 400, height: 300), display: false)
            store.registerOwnWindow(window)
            let entry = try #require(store.windows.first)
            #expect(!entry.isOn(screen: screen))

            window.setFrame(
                NSRect(
                    x: screen.frame.midX, y: screen.frame.midY,
                    width: 400, height: 300), display: false)

            #expect(entry.isOn(screen: screen))
        }

        /// An open session must be told to look again when Settings is dragged.
        @Test func moveAndResizeNotifyAnOpenSession() {
            store.registerOwnWindow(window)
            var changes = 0
            store.onChange = { changes += 1 }

            NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)

            #expect(changes == 2)
        }

        /// Closing removes every observation, including the new geometry ones.
        @Test func closingStopsGeometryNotifications() {
            store.registerOwnWindow(window)
            window.close()
            var changes = 0
            store.onChange = { changes += 1 }

            NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)

            #expect(changes == 0)
        }

        /// External AX windows keep the Quartz conversion: a screen below the
        /// primary one has a positive Quartz origin, not a negative Cocoa one.
        @Test func screenQuartzFrameFlipsAroundThePrimaryDisplay() {
            let primaryFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let belowFrame = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
            // mirrors TrackedWindow.quartzFrame's arithmetic on plain rectangles
            func quartz(_ frame: CGRect) -> CGRect {
                CGRect(
                    x: frame.origin.x, y: primaryFrame.maxY - frame.maxY,
                    width: frame.width, height: frame.height)
            }

            #expect(quartz(primaryFrame).origin.y == 0)
            #expect(quartz(belowFrame).origin.y == 1080)
            #expect(!quartz(primaryFrame).intersects(quartz(belowFrame)))
        }
    }
}
