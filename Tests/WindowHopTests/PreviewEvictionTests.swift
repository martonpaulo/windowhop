import AppKit
import XCTest
@testable import WindowHopCore

/// A removed window's stable id must never outlive it in the preview cache.
/// Every removal path in the store goes through one eviction handoff; these
/// drive the real entry points and observe the provider's cache.
final class PreviewEvictionTests: XCTestCase {
    private var store: WindowStore!
    private var window: NSWindow!
    private var seeded: [AnyHashable] = []

    override func setUp() {
        super.setUp()
        store = WindowStore()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        // the provider is a singleton: leave no test ids behind
        seeded.forEach { PreviewProvider.shared.evict($0) }
        seeded = []
        window = nil
        store = nil
        super.tearDown()
    }

    /// Seeds the cache for every current entry, as a finished capture would.
    private func seedPreviews() -> [AnyHashable] {
        let ids = store.windows.map { $0.stableId as AnyHashable }
        for id in ids {
            PreviewProvider.shared.storeForTesting(NSImage(size: NSSize(width: 8, height: 8)),
                                                   for: id)
        }
        seeded.append(contentsOf: ids)
        return ids
    }

    private func cached(_ ids: [AnyHashable]) -> [AnyHashable] {
        ids.filter { PreviewProvider.shared.cachedPreview(for: $0) != nil }
    }

    func testClosingTheSettingsWindowEvictsItsPreview() {
        store.registerOwnWindow(window)
        let ids = seedPreviews()
        XCTAssertEqual(cached(ids).count, 1)

        window.close()

        XCTAssertTrue(cached(ids).isEmpty, "the closed Settings entry kept its preview")
    }

    /// Reopening mints a fresh identity, so without eviction each cycle leaves
    /// one more orphan behind.
    func testRepeatedSettingsCyclesLeaveNoOrphans() {
        var allIds: [AnyHashable] = []
        for _ in 0..<5 {
            // Settings is recreated on each open, exactly like the real controller
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                    styleMask: [.titled, .closable], backing: .buffered,
                                    defer: true)
            settings.isReleasedWhenClosed = false
            store.registerOwnWindow(settings)
            allIds.append(contentsOf: seedPreviews())
            settings.close()
        }

        XCTAssertEqual(Set(allIds).count, 5, "each cycle must mint a fresh id")
        XCTAssertTrue(cached(allIds).isEmpty)
    }

    func testStoppingTheStoreEvictsTheWholeInventory() {
        store.registerOwnWindow(window)
        let ids = seedPreviews()

        store.start()
        store.stop()

        XCTAssertTrue(cached(ids).isEmpty)
        XCTAssertTrue(store.windows.isEmpty)
    }

    /// A capture that lands after eviction must not resurrect the id.
    func testALateCaptureCannotRestoreAnEvictedPreview() {
        store.registerOwnWindow(window)
        let ids = seedPreviews()
        window.close()

        for id in ids where PreviewProvider.shared.ledgerShouldStoreForTesting(id) {
            XCTFail("an evicted id must not accept a late capture")
        }
        XCTAssertTrue(cached(ids).isEmpty)
    }

    /// The control: an entry that is still open keeps its cached preview when
    /// the session merely ends.
    func testEndingASessionKeepsLivingWindowsWarm() {
        store.registerOwnWindow(window)
        let ids = seedPreviews()

        PreviewProvider.shared.endSession()

        XCTAssertEqual(cached(ids).count, 1)
    }
}

/// Views hold a preview image only while they present it; between sessions
/// the provider cache is the only warm owner (#54). Each image is created in
/// an autorelease pool and observed through a weak reference, so these fail
/// if any hidden, collapsed, or ended view still retains it.
final class PreviewViewReleaseTests: XCTestCase {
    private var savedAppearanceMode: AppearanceMode!
    private var seeded: [AnyHashable] = []

    override func setUp() {
        super.setUp()
        savedAppearanceMode = Preferences.shared.appearanceMode
        Preferences.shared.appearanceMode = .windowPreviews
    }

    override func tearDown() {
        seeded.forEach { PreviewProvider.shared.evict($0) }
        seeded = []
        Preferences.shared.appearanceMode = savedAppearanceMode
        super.tearDown()
    }

    private func item(_ id: String) -> SwitcherItem {
        SwitcherItem(id: id, window: nil, title: "Window \(id)",
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

    func testASlotHiddenByAnUpdateReleasesItsImage() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        let image = weakImage { panel.updatePreview(id: "b", image: $0) }
        XCTAssertNotNil(image(), "the visible tile presents the image")

        drained { panel.update(items: [item("a")], selectedIndex: 0) }

        XCTAssertNil(image(), "a hidden slot kept a removed window's image")
    }

    func testReleasedHiddenTilesDoNotPulse() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Reduce Motion is on, so no skeleton ever pulses")
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        let hidden = try XCTUnwrap(panel.tileForTesting(at: 1))
        XCTAssertTrue(hidden.skeletonIsAnimatingForTesting, "a loading tile pulses")

        panel.update(items: [item("a")], selectedIndex: 0)

        XCTAssertFalse(hidden.skeletonIsAnimatingForTesting)
    }

    func testHidingTheExpandedPreviewReleasesItsImage() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a")], selectedIndex: 0)
        let image = weakImage { panel.showExpandedPreview(id: "a", image: $0) }
        XCTAssertNotNil(image())

        drained { panel.hideExpandedPreview() }

        XCTAssertNil(image())
    }

    func testAnUpdateThatCollapsesTheExpandedPreviewReleasesItsImage() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        let image = weakImage { panel.showExpandedPreview(id: "a", image: $0) }

        // the expanded window leaves the list
        drained { panel.update(items: [item("b")], selectedIndex: 0) }

        XCTAssertNil(panel.expandedPreviewID)
        XCTAssertNil(image())
    }

    func testEndingASessionReleasesViewsButKeepsTheWarmCache() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        let delivered = weakImage { panel.updatePreview(id: "a", image: $0) }
        let expanded = weakImage { panel.showExpandedPreview(id: "b", image: $0) }
        seeded.append("b")
        PreviewProvider.shared.storeForTesting(NSImage(size: NSSize(width: 40, height: 30)),
                                               for: "b")

        drained {
            panel.hideExpandedPreview()
            panel.hide()
            panel.releasePreviewContent()
        }

        XCTAssertNil(delivered(), "a tile kept its image after the session ended")
        XCTAssertNil(expanded())
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 0))
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 1))

        // the next session reloads the living window straight from the cache
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        XCTAssertTrue(panel.tileShowsPreviewForTesting(at: 1))
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 0))
    }
}
