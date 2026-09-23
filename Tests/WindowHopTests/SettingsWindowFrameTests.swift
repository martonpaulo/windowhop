import AppKit
import Testing

@testable import WindowHopCore

extension SharedAppState {
    /// The Settings window's position survives relaunch through AppKit's frame
    /// autosave, while its size always comes from the shared pane canvas.
    /// Each test uses its own autosave name and removes AppKit's key afterwards.
    @MainActor
    final class SettingsWindowFrameTests {
        private var autosaveName = ""
        private var windows: [NSWindow] = []
        private var isolated: IsolatedPreferences!

        private var defaultsKey: String { "NSWindow Frame \(autosaveName)" }

        init() throws {
            _ = NSApplication.shared
            isolated = try IsolatedPreferences()
            autosaveName = "WindowHopSettingsTest-\(UUID().uuidString)"
        }

        isolated deinit {
            for window in windows {
                window.setFrameAutosaveName("")
                window.close()
            }
            windows = []
            isolated.remove()
            isolated = nil
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        /// A new controller stands in for a new process: nothing retained.
        private func launch() -> NSWindow {
            let window = SettingsWindowController(
                dependencies: isolated.settingsDependencies,
                registerOwnWindow: { _ in },
                frameAutosaveName: autosaveName
            ).preparedWindow()
            windows.append(window)
            return window
        }

        /// Releases the autosave name, as quitting does, so the next launch can claim it.
        private func quit(_ window: NSWindow) {
            window.setFrameAutosaveName("")
        }

        private var screen: CGRect {
            NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        }

        @Test(.disabled("no display") { await MainActor.run { NSScreen.main == nil } })
        func firstUseIsCentered() throws {
            #expect(UserDefaults.standard.string(forKey: defaultsKey) == nil)
            let window = launch()
            // AppKit's center() puts the window slightly above the true center
            #expect(abs(window.frame.midX - screen.midX) <= 2)
            #expect(screen.contains(window.frame))
        }

        @Test(.disabled("no display") { await MainActor.run { NSScreen.main == nil } })
        func movedPositionIsRestoredOnNextLaunch() throws {
            let first = launch()
            let origin = CGPoint(x: screen.minX + 40, y: screen.minY + 30)
            first.setFrameOrigin(origin)
            #expect(
                UserDefaults.standard.string(forKey: defaultsKey) != nil,
                "AppKit saves the moved frame under the autosave name")
            quit(first)

            let second = launch()
            #expect(second.frame.origin == origin)
            #expect(second.frame.size == first.frame.size)
        }

        @Test(.disabled("no display") { await MainActor.run { NSScreen.main == nil } })
        func savedFrameOfAnotherSizeKeepsTheCanvasSize() throws {
            let canvasSize = launch().frame.size
            windows.forEach(quit)

            // a frame saved by a build whose canvas had another size
            let old = NSWindow(
                contentRect: .zero, styleMask: [.titled, .resizable],
                backing: .buffered, defer: true)
            old.isReleasedWhenClosed = false
            windows.append(old)
            // anchored to the top with room below, so restoring the taller canvas never makes
            // AppKit push the window back on screen (CI runners have small displays)
            if screen.height < canvasSize.height + 80 {
                try Test.cancel("display too small to restore the canvas")
            }
            let savedHeight = canvasSize.height - 80
            let savedFrame = CGRect(
                x: screen.minX + 60, y: screen.maxY - 20 - savedHeight,
                width: canvasSize.width + 120, height: savedHeight)
            old.setFrame(savedFrame, display: false)
            old.saveFrame(usingName: autosaveName)

            let restored = launch()
            #expect(restored.frame.size == canvasSize)
            #expect(restored.frame.minX == savedFrame.minX)
            #expect(restored.frame.maxY == savedFrame.maxY, "the title bar stays where it was")
        }

        @Test func savedFrameOnVanishedDisplayIsRecovered() throws {
            let main = try #require(NSScreen.main)
            let first = launch()
            quit(first)
            // far beyond every connected display
            let offScreen = CGRect(x: 100_000, y: 100_000, width: first.frame.width, height: first.frame.height)
            let old = NSWindow(
                contentRect: .zero, styleMask: [.titled],
                backing: .buffered, defer: true)
            old.isReleasedWhenClosed = false
            windows.append(old)
            old.setFrame(offScreen, display: false)
            old.saveFrame(usingName: autosaveName)

            let restored = launch()
            #expect(main.visibleFrame.contains(restored.frame))
            #expect(restored.frame.size == first.frame.size)
        }

        @Test func switchingPanesKeepsTheWindowSize() throws {
            let window = launch()
            let tabs = try #require(window.contentViewController as? NSTabViewController)
            let original = tabs.selectedTabViewItemIndex
            let size = window.frame.size
            for index in tabs.tabViewItems.indices {
                tabs.selectedTabViewItemIndex = index
                #expect(window.frame.size == size, "pane \(index)")
            }
            tabs.selectedTabViewItemIndex = original
        }
    }
}
