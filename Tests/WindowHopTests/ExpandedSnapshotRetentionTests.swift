import AppKit
import XCTest

@testable import WindowHopCore

/// A dwell snapshot is several times a tile's raster. It must never become the
/// app-lifetime cached preview of a window: the provider keeps at most one, for
/// the current session, while the tile keeps its own tile-sized snapshot (#87).
@MainActor
final class ExpandedSnapshotRetentionTests: XCTestCase {
    private var isolated: IsolatedPreferences!
    private var provider: PreviewProvider { isolated.previews }
    private var seeded: [AnyHashable] = []

    override func setUp() async throws {
        try await super.setUp()
        isolated = try IsolatedPreferences()
    }

    override func tearDown() async throws {
        seeded = []
        provider.endSession()
        isolated.remove()
        isolated = nil
        try await super.tearDown()
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

    func testAnExpandedCaptureNeverReplacesTheCachedTile() {
        let tile = seedTile("a")

        let expanded = deliverExpanded(for: "a")

        XCTAssertTrue(provider.cachedPreview(for: "a") === tile)
        XCTAssertNotNil(expanded())
        XCTAssertTrue(provider.expandedPreview(for: "a") === expanded())
    }

    func testEndingTheSessionReleasesTheExpandedImageButKeepsTheTile() {
        let tile = seedTile("a")
        let expanded = deliverExpanded(for: "a")

        autoreleasepool { provider.endSession() }

        XCTAssertNil(expanded(), "the expanded image outlived its session")
        XCTAssertTrue(provider.cachedPreview(for: "a") === tile)
        XCTAssertTrue(provider.expandedPreview(for: "a") === tile)
    }

    func testOnlyTheLatestExpandedImageIsRetained() {
        let tileA = seedTile("a")
        _ = seedTile("b")
        let first = deliverExpanded(for: "a")

        let second = deliverExpanded(for: "b")

        XCTAssertNil(first(), "visiting a second window kept the first expanded image")
        XCTAssertNotNil(second())
        XCTAssertTrue(provider.expandedPreview(for: "a") === tileA)
    }

    func testEvictingTheWindowReleasesItsExpandedImage() {
        _ = seedTile("a")
        let expanded = deliverExpanded(for: "a")

        autoreleasepool { provider.evict("a") }

        XCTAssertNil(expanded())
        XCTAssertNil(provider.expandedPreview(for: "a"))
    }

    func testRetargetingWithinTheSessionKeepsTheLastExpandedImage() {
        _ = seedTile("a")
        let expanded = deliverExpanded(for: "a")

        provider.cancelExpandedPreview()

        XCTAssertNotNil(expanded())
        XCTAssertTrue(provider.expandedPreview(for: "a") === expanded())
    }
}
