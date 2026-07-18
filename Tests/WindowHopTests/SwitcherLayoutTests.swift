import AppKit
import XCTest
@testable import WindowHopCore

final class SwitcherLayoutTests: XCTestCase {
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

    func testOverlaysStayCanvasAlignedAcrossSourceAspectRatios() {
        let wide = configuredTile(imageSize: NSSize(width: 400, height: 100))
        let tall = configuredTile(imageSize: NSSize(width: 100, height: 400))

        XCTAssertEqual(wide.previewCanvasFrameForTesting, tall.previewCanvasFrameForTesting)
        XCTAssertEqual(wide.badgeFrameForTesting, tall.badgeFrameForTesting)
        XCTAssertEqual(wide.closeFrameForTesting, tall.closeFrameForTesting)
        XCTAssertNotEqual(wide.previewImageFrameForTesting, tall.previewImageFrameForTesting)
        XCTAssertEqual(wide.badgeFrameForTesting.maxX,
                       wide.previewCanvasFrameForTesting.maxX + DesignTokens.previewOverlayOverlap)
        XCTAssertEqual(wide.badgeFrameForTesting.minY,
                       wide.previewCanvasFrameForTesting.minY - DesignTokens.previewOverlayOverlap)
        XCTAssertLessThanOrEqual(wide.badgeFrameForTesting.maxX, wide.bounds.maxX)
        XCTAssertGreaterThanOrEqual(wide.badgeFrameForTesting.minY, wide.bounds.minY)

        let loading = configuredTile(imageSize: nil)
        XCTAssertEqual(loading.previewCanvasFrameForTesting, wide.previewCanvasFrameForTesting)
        XCTAssertEqual(loading.badgeFrameForTesting, wide.badgeFrameForTesting)
    }

    func testPreviewOutlineHierarchyHasThreeDistinctStrengths() {
        let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
        XCTAssertEqual(tile.previewOutlineWidthForTesting, DesignTokens.previewOutlineWidth)

        tile.isTemporarilyActive = true
        XCTAssertEqual(tile.previewOutlineWidthForTesting,
                       DesignTokens.previewEmphasisOutlineWidth)

        tile.isSelected = true
        XCTAssertEqual(tile.previewOutlineWidthForTesting,
                       DesignTokens.previewSelectionOutlineWidth)
        XCTAssertEqual(tile.previewSelectionBackingAlphaForTesting, 0,
                       "the selected preview must not retain a second backing outline")

        let loading = configuredTile(imageSize: nil)
        loading.isSelected = true
        XCTAssertEqual(loading.previewOutlineWidthForTesting,
                       DesignTokens.previewSelectionOutlineWidth)
        XCTAssertEqual(loading.previewSelectionBackingAlphaForTesting, 0)
    }

    func testPanelUsesOneHorizontalSpacingAndNoSettingsChromeRow() throws {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
        let first = try XCTUnwrap(panel.tileFrameForTesting(at: 0))
        let second = try XCTUnwrap(panel.tileFrameForTesting(at: 1))

        XCTAssertEqual(second.minX - first.maxX, DesignTokens.tileSpacing)
        XCTAssertEqual(panel.panelBackgroundFrameForTesting.height,
                       panel.gridFrameForTesting.height + DesignTokens.panelPadding * 2)
        XCTAssertEqual(panel.settingsButtonFrameForTesting.midX,
                       panel.panelBackgroundFrameForTesting.maxX)
        XCTAssertEqual(panel.settingsButtonFrameForTesting.midY,
                       panel.panelBackgroundFrameForTesting.maxY)
        XCTAssertEqual(panel.frame.width,
                       panel.panelBackgroundFrameForTesting.width
                           + DesignTokens.chromeButtonHitSize / 2)
        XCTAssertEqual(panel.frame.height,
                       panel.panelBackgroundFrameForTesting.height
                           + DesignTokens.chromeButtonHitSize / 2)
    }

    private func configuredTile(imageSize: NSSize?) -> SwitcherTileView {
        let tile = SwitcherTileView()
        tile.configure(item: item("tile"), mode: .windowPreviews,
                       preview: imageSize.map(NSImage.init(size:)))
        tile.frame = NSRect(origin: .zero,
                            size: SwitcherTileView.Metrics.metrics(for: .windowPreviews).tileSize)
        tile.layoutSubtreeIfNeeded()
        return tile
    }

    private func item(_ id: String) -> SwitcherItem {
        SwitcherItem(id: id, window: nil, title: "Window \(id)",
                     appName: "TestApp", icon: nil, tabCount: nil)
    }
}
