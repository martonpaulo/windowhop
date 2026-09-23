import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// A removed window's stable id must never outlive it in the preview cache.
    /// Every removal path in the store goes through one eviction handoff; these
    /// drive the real entry points and observe the provider's cache.
    @MainActor
    final class PreviewEvictionTests {
        private var isolated: IsolatedPreferences!
        private var previews: PreviewProvider { isolated.previews }
        private var store: WindowStore!
        private var window: NSWindow!
        private var seeded: [AnyHashable] = []

        init() throws {
            isolated = try IsolatedPreferences()
            store = WindowStore(preferences: isolated.preferences, previews: isolated.previews)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
        }

        isolated deinit {
            seeded = []
            window = nil
            store = nil
            isolated.remove()
            isolated = nil
        }

        /// Seeds the cache for every current entry, as a finished capture would.
        private func seedPreviews() -> [AnyHashable] {
            let ids = store.windows.map { $0.stableId as AnyHashable }
            for id in ids {
                previews.storeForTesting(
                    NSImage(size: NSSize(width: 8, height: 8)),
                    for: id)
            }
            seeded.append(contentsOf: ids)
            return ids
        }

        private func cached(_ ids: [AnyHashable]) -> [AnyHashable] {
            ids.filter { previews.cachedPreview(for: $0) != nil }
        }

        @Test func closingTheSettingsWindowEvictsItsPreview() {
            store.registerOwnWindow(window)
            let ids = seedPreviews()
            #expect(cached(ids).count == 1)

            window.close()

            #expect(cached(ids).isEmpty, "the closed Settings entry kept its preview")
        }

        /// Reopening mints a fresh identity, so without eviction each cycle leaves
        /// one more orphan behind.
        @Test func repeatedSettingsCyclesLeaveNoOrphans() {
            var allIds: [AnyHashable] = []
            for _ in 0..<5 {
                // Settings is recreated on each open, exactly like the real controller
                let settings = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                    styleMask: [.titled, .closable], backing: .buffered,
                    defer: true)
                settings.isReleasedWhenClosed = false
                store.registerOwnWindow(settings)
                allIds.append(contentsOf: seedPreviews())
                settings.close()
            }

            #expect(Set(allIds).count == 5, "each cycle must mint a fresh id")
            #expect(cached(allIds).isEmpty)
        }

        @Test func stoppingTheStoreEvictsTheWholeInventory() {
            store.registerOwnWindow(window)
            let ids = seedPreviews()

            store.start()
            store.stop()

            #expect(cached(ids).isEmpty)
            #expect(store.windows.isEmpty)
        }

        /// A capture that lands after eviction must not resurrect the id.
        @Test func aLateCaptureCannotRestoreAnEvictedPreview() {
            store.registerOwnWindow(window)
            let ids = seedPreviews()
            window.close()

            for id in ids where previews.ledgerShouldStoreForTesting(id) {
                Issue.record("an evicted id must not accept a late capture")
            }
            #expect(cached(ids).isEmpty)
        }

        /// The control: an entry that is still open keeps its cached preview when
        /// the session merely ends.
        @Test func endingASessionKeepsLivingWindowsWarm() {
            store.registerOwnWindow(window)
            let ids = seedPreviews()

            previews.endSession()

            #expect(cached(ids).count == 1)
        }
    }
}

extension SharedAppState {
    /// Views hold a preview image only while they present it; between sessions
    /// the provider cache is the only warm owner (#54). Each image is created in
    /// an autorelease pool and observed through a weak reference, so these fail
    /// if any hidden, collapsed, or ended view still retains it.
    @MainActor
    final class PreviewViewReleaseTests {
        private var isolated: IsolatedPreferences!
        private var preferences: Preferences { isolated.preferences }
        private var previews: PreviewProvider { isolated.previews }
        private var seeded: [AnyHashable] = []

        init() throws {
            isolated = try IsolatedPreferences()
            preferences.appearanceMode = .windowPreviews
        }

        isolated deinit {
            seeded = []
            isolated.remove()
            isolated = nil
        }

        private func item(_ id: String) -> SwitcherItem {
            SwitcherItem(
                id: id, window: nil, title: "Window \(id)",
                appName: "TestApp", icon: nil, tabCount: nil)
        }

        /// Hands a fresh image to `deliver` and returns only a weak reference.
        private func weakImage(_ deliver: (NSImage) -> Void) -> () -> NSImage? {
            weak var reference: NSImage?
            autoreleasepool {
                let image = NSImage(size: NSSize(width: 40, height: 30))
                reference = image
                deliver(image)
            }
            return { reference }
        }

        /// Runs a release step and drains the autorelease pool it fills, as the
        /// run loop would after the event that triggered it.
        private func drained(_ body: () -> Void) {
            autoreleasepool(invoking: body)
        }

        @Test func aSlotHiddenByAnUpdateReleasesItsImage() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            let image = weakImage { panel.updatePreview(id: "b", image: $0) }
            #expect(image() != nil, "the visible tile presents the image")

            drained { panel.update(items: [item("a")], selectedIndex: 0) }

            #expect(image() == nil, "a hidden slot kept a removed window's image")
        }

        @Test(
            .disabled(
                if: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "Reduce Motion is on, so no skeleton ever pulses"))
        func releasedHiddenTilesDoNotPulse() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            let hidden = try #require(panel.tileForTesting(at: 1))
            #expect(hidden.skeletonIsAnimatingForTesting, "a loading tile pulses")

            panel.update(items: [item("a")], selectedIndex: 0)

            #expect(!hidden.skeletonIsAnimatingForTesting)
        }

        @Test func hidingTheExpandedPreviewReleasesItsImage() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a")], selectedIndex: 0)
            let image = weakImage { panel.showExpandedPreview(id: "a", image: $0) }
            #expect(image() != nil)

            drained { panel.hideExpandedPreview() }

            #expect(image() == nil)
        }

        @Test func anUpdateThatCollapsesTheExpandedPreviewReleasesItsImage() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            let image = weakImage { panel.showExpandedPreview(id: "a", image: $0) }

            // the expanded window leaves the list
            drained { panel.update(items: [item("b")], selectedIndex: 0) }

            #expect(panel.expandedPreviewID == nil)
            #expect(image() == nil)
        }

        @Test func endingASessionReleasesViewsButKeepsTheWarmCache() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            let delivered = weakImage { panel.updatePreview(id: "a", image: $0) }
            let expanded = weakImage { panel.showExpandedPreview(id: "b", image: $0) }
            seeded.append("b")
            previews.storeForTesting(
                NSImage(size: NSSize(width: 40, height: 30)),
                for: "b")

            drained {
                panel.hideExpandedPreview()
                panel.hide()
                panel.releasePreviewContent()
            }

            #expect(delivered() == nil, "a tile kept its image after the session ended")
            #expect(expanded() == nil)
            #expect(!panel.tileShowsPreviewForTesting(at: 0))
            #expect(!panel.tileShowsPreviewForTesting(at: 1))

            // the next session reloads the living window straight from the cache
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            #expect(panel.tileShowsPreviewForTesting(at: 1))
            #expect(!panel.tileShowsPreviewForTesting(at: 0))
        }
    }
}
