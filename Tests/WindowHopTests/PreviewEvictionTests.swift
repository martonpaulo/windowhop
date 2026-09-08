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
