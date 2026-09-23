import AppKit
import XCTest

@testable import WindowHopCore
@testable import WindowHopKit

/// A list refresh during a session keeps every window on the tile that
/// already shows it and reconfigures only tiles whose data changed (#119).
/// A snapshot delivered straight to a tile (never in the provider cache in
/// these tests) is the observable proof that a tile was not reconfigured.
@MainActor
final class SwitcherTileReuseTests: XCTestCase {
    private var isolated: IsolatedPreferences!
    private var preferences: Preferences { isolated.preferences }
    private var previews: PreviewProvider { isolated.previews }

    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedPreferences()
        preferences.appearanceMode = .windowPreviews
    }

    override func tearDown() async throws {
        isolated.remove()
        isolated = nil
        try await super.tearDown()
    }

    private func item(_ id: String, title: String? = nil) -> SwitcherItem {
        SwitcherItem(
            id: id, window: nil, title: title ?? "Window \(id)",
            appName: "TestApp", icon: nil, tabCount: nil)
    }

    private var image: NSImage { NSImage(size: NSSize(width: 40, height: 30)) }

    private func tile(_ panel: SwitcherPanel, _ index: Int) throws -> SwitcherTileView {
        try XCTUnwrap(panel.tileForTesting(at: index))
    }

    func testUnchangedRefreshKeepsEveryTileAsItIs() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        panel.updatePreview(id: "a", image: image)
        let first = try tile(panel, 0)

        panel.update(items: [item("a"), item("b")], selectedIndex: 0)

        XCTAssertTrue(try tile(panel, 0) === first)
        XCTAssertTrue(
            panel.tileShowsPreviewForTesting(at: 0),
            "an unchanged tile was reconfigured")
    }

    func testChangedTitleReconfiguresOnlyThatTile() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        panel.updatePreview(id: "a", image: image)

        panel.update(items: [item("a"), item("b", title: "Renamed")], selectedIndex: 0)

        XCTAssertTrue(panel.tileShowsPreviewForTesting(at: 0))
        XCTAssertEqual(try tile(panel, 1).accessibilityLabel(), "Renamed, TestApp")
    }

    func testReorderedWindowKeepsItsTileAndSnapshot() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.update(items: [item("a"), item("b")], selectedIndex: 0)
        panel.updatePreview(id: "b", image: image)
        let bTile = try tile(panel, 1)

        panel.update(items: [item("b"), item("a")], selectedIndex: 0)

        XCTAssertTrue(try tile(panel, 0) === bTile)
        XCTAssertTrue(panel.tileShowsPreviewForTesting(at: 0))
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 1))
    }

    func testAppearanceChangeReconfiguresEveryTile() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.update(items: [item("a")], selectedIndex: 0)
        panel.updatePreview(id: "a", image: image)

        preferences.appearanceMode = .appIcons
        panel.update(items: [item("a")], selectedIndex: 0)

        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 0))
    }

    func testANewSessionReconfiguresTilesItAlreadyShowed() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.show(items: [item("a")], selectedIndex: 0, presentationMode: .persistent)
        panel.updatePreview(id: "a", image: image)
        panel.hide()

        panel.show(items: [item("a")], selectedIndex: 0, presentationMode: .persistent)
        panel.hide()

        // the provider cache holds nothing for "a", so a fresh configure
        // shows no snapshot; a skipped one would still show the old image
        XCTAssertFalse(panel.tileShowsPreviewForTesting(at: 0))
    }

    func testClickReportsTheTilesCurrentPositionAfterItMoved() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        var clicked: [Int] = []
        var closeRequested: [Int] = []
        panel.onItemClicked = { clicked.append($0) }
        panel.onItemCloseRequested = { closeRequested.append($0) }
        panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
        let cTile = try tile(panel, 2)

        panel.update(items: [item("b"), item("c")], selectedIndex: 0)

        XCTAssertTrue(try tile(panel, 1) === cTile)
        XCTAssertTrue(cTile.accessibilityPerformPress())
        cTile.onCloseRequest?()
        XCTAssertEqual(clicked, [1])
        XCTAssertEqual(closeRequested, [1])
    }

    func testTileOrderFollowsItemOrderAfterANewWindowTakesAFreedSlot() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
        panel.update(items: [item("b"), item("c"), item("new")], selectedIndex: 0)

        let tiles = try (0..<3).map { try tile(panel, $0) }
        let container = try XCTUnwrap(tiles[0].superview)
        let visibleOrder = container.subviews.filter { !$0.isHidden }
        XCTAssertTrue(
            visibleOrder.elementsEqual(tiles, by: ===),
            "accessibility order must match the item order")
        XCTAssertEqual(try tile(panel, 2).accessibilityLabel(), "Window new, TestApp")
    }

    func testSelectionChangeRestylesOnlyTheTilesItAffects() throws {
        let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
        panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
        for index in 0..<3 { try tile(panel, index).layoutSubtreeIfNeeded() }

        panel.select(1)

        XCTAssertTrue(try tile(panel, 0).needsLayout)
        XCTAssertTrue(try tile(panel, 1).needsLayout)
        XCTAssertFalse(
            try tile(panel, 2).needsLayout,
            "an unaffected tile was restyled")
    }
}
