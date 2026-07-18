import AppKit
import XCTest
@testable import WindowHopCore

/// Preview/window association at the view layer: deliveries are keyed by the
/// window's stable id, pooled tiles reset stale image state when they start
/// representing another window, and rapid list changes can never move a
/// snapshot onto a different card.
final class PreviewAssociationTests: XCTestCase {
    private var savedAppearanceMode: AppearanceMode!

    override func setUp() {
        super.setUp()
        savedAppearanceMode = Preferences.shared.appearanceMode
        Preferences.shared.appearanceMode = .windowPreviews
    }

    override func tearDown() {
        Preferences.shared.appearanceMode = savedAppearanceMode
        super.tearDown()
    }

    private func item(_ id: String) -> SwitcherItem {
        SwitcherItem(id: id, window: nil, title: "Window \(id)",
                     appName: "TestApp", icon: nil, tabCount: nil)
    }

    private var image: NSImage { NSImage(size: NSSize(width: 40, height: 30)) }

    func testReusedTileResetsStaleImageState() {
        let tile = SwitcherTileView()
        tile.configure(item: item("a"), mode: .windowPreviews,
                       showTabCounts: false, preview: image)
        XCTAssertTrue(tile.showsPreviewImage)
        // the pooled tile now represents a window with no snapshot: nothing of
        // the previous occupant may remain visible
        tile.configure(item: item("b"), mode: .windowPreviews,
                       showTabCounts: false, preview: nil)
        XCTAssertFalse(tile.showsPreviewImage)
    }

    func testDeliveryIsKeyedByWindowIdNotTilePosition() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        panel.updatePreview(id: "b", image: image)
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 0))
        XCTAssertTrue(panel.tileShowsPreviewForTesting(at: 1))
    }

    func testReorderingNeverMovesASnapshotToAnotherCard() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        panel.updatePreview(id: "b", image: image)
        // the tile that showed b's snapshot now represents a — it must not
        // keep the old image (there is no cached snapshot for either window)
        panel.update(items: [item("b"), item("a")], selectedIndex: 0)
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 1))
    }

    func testDeliveryForARemovedWindowIsIgnored() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
        panel.updatePreview(id: "b", image: image)
        // b closes mid-session; a late capture for it must go nowhere
        panel.update(items: [item("a"), item("c")], selectedIndex: 0)
        panel.updatePreview(id: "b", image: image)
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 0))
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 1))
    }
}
