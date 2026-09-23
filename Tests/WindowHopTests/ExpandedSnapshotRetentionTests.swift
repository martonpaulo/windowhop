import AppKit
import Testing

@testable import WindowHopCore

extension SharedAppState {
    /// A dwell snapshot is several times a tile's raster. It must never become the
    /// app-lifetime cached preview of a window: the provider keeps at most one, for
    /// the current session, while the tile keeps its own tile-sized snapshot (#87).
    @MainActor
    final class ExpandedSnapshotRetentionTests {
        private var isolated: IsolatedPreferences!
        private var provider: PreviewProvider { isolated.previews }
        private var seeded: [AnyHashable] = []

        init() throws {
            isolated = try IsolatedPreferences()
        }

        isolated deinit {
            seeded = []
            provider.endSession()
            isolated.remove()
            isolated = nil
        }

        private func seedTile(_ id: AnyHashable) -> NSImage {
            let tile = NSImage(size: NSSize(width: 188, height: 118))
            provider.storeForTesting(tile, for: id)
            seeded.append(id)
            return tile
        }

        /// Delivers a fresh expanded image and returns only a weak reference.
        private func deliverExpanded(for id: AnyHashable) -> () -> NSImage? {
            weak var reference: NSImage?
            autoreleasepool {
                let image = NSImage(size: NSSize(width: 672, height: 382))
                reference = image
                provider.deliverExpandedSnapshot(image, for: id)
            }
            return { reference }
        }

        @Test func anExpandedCaptureNeverReplacesTheCachedTile() {
            let tile = seedTile("a")

            let expanded = deliverExpanded(for: "a")

            #expect(provider.cachedPreview(for: "a") === tile)
            #expect(expanded() != nil)
            #expect(provider.expandedPreview(for: "a") === expanded())
        }

        @Test func endingTheSessionReleasesTheExpandedImageButKeepsTheTile() {
            let tile = seedTile("a")
            let expanded = deliverExpanded(for: "a")

            autoreleasepool { provider.endSession() }

            #expect(expanded() == nil, "the expanded image outlived its session")
            #expect(provider.cachedPreview(for: "a") === tile)
            #expect(provider.expandedPreview(for: "a") === tile)
        }

        @Test func onlyTheLatestExpandedImageIsRetained() {
            let tileA = seedTile("a")
            _ = seedTile("b")
            let first = deliverExpanded(for: "a")

            let second = deliverExpanded(for: "b")

            #expect(first() == nil, "visiting a second window kept the first expanded image")
            #expect(second() != nil)
            #expect(provider.expandedPreview(for: "a") === tileA)
        }

        @Test func evictingTheWindowReleasesItsExpandedImage() {
            _ = seedTile("a")
            let expanded = deliverExpanded(for: "a")

            autoreleasepool { provider.evict("a") }

            #expect(expanded() == nil)
            #expect(provider.expandedPreview(for: "a") == nil)
        }

        @Test func retargetingWithinTheSessionKeepsTheLastExpandedImage() {
            _ = seedTile("a")
            let expanded = deliverExpanded(for: "a")

            provider.cancelExpandedPreview()

            #expect(expanded() != nil)
            #expect(provider.expandedPreview(for: "a") === expanded())
        }
    }
}
