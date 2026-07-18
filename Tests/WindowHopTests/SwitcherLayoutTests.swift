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
        XCTAssertTrue(loading.showsLoadingStateForTesting)
        XCTAssertEqual(loading.previewCanvasFrameForTesting, wide.previewCanvasFrameForTesting)
        XCTAssertEqual(loading.badgeFrameForTesting, wide.badgeFrameForTesting)
    }

    func testEveryPreviewStateUsesTheSameSingleSelectionOutline() {
        let loaded = configuredTile(imageSize: NSSize(width: 300, height: 200))
        let loading = configuredTile(imageSize: nil)
        let unavailable = configuredTile(imageSize: nil)
        unavailable.setPreviewUnavailable()
        unavailable.layoutSubtreeIfNeeded()

        for tile in [loaded, loading, unavailable] {
            tile.isSelected = true
            XCTAssertEqual(tile.previewOutlineWidthForTesting,
                           DesignTokens.selectionOutlineWidth)
            XCTAssertEqual(tile.previewOutlineCornerRadiusForTesting,
                           DesignTokens.cardCornerRadius)
        }
        XCTAssertEqual(loaded.previewOutlineColorForTesting,
                       loading.previewOutlineColorForTesting)
        XCTAssertEqual(loaded.previewOutlineColorForTesting,
                       unavailable.previewOutlineColorForTesting)
        XCTAssertTrue(unavailable.showsUnavailableStateForTesting)
    }

    func testIconOnlyCardsUseBackgroundSelectionWithoutAnyOutline() {
        let tile = configuredTile(imageSize: nil, mode: .appIcons)

        XCTAssertFalse(tile.showsCardOutlineForTesting)
        XCTAssertEqual(tile.selectionBackgroundAlphaForTesting, 0)
        tile.isSelected = true
        XCTAssertFalse(tile.showsCardOutlineForTesting)
        XCTAssertEqual(tile.selectionBackgroundAlphaForTesting,
                       DesignTokens.iconSelectionFill.alphaComponent)
    }

    func testOutlineHierarchyReplacesNeutralWithOneSelectedOutline() {
        let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
        XCTAssertEqual(tile.previewOutlineWidthForTesting, DesignTokens.previewOutlineWidth)

        tile.isTemporarilyActive = true
        XCTAssertEqual(tile.previewOutlineWidthForTesting,
                       DesignTokens.previewEmphasisOutlineWidth)

        tile.isSelected = true
        XCTAssertEqual(tile.previewOutlineWidthForTesting,
                       DesignTokens.selectionOutlineWidth)
        XCTAssertGreaterThan(DesignTokens.selectionOutlineWidth,
                             DesignTokens.previewEmphasisOutlineWidth)
    }

    func testSelectionColorAdaptsBetweenLightAndDarkAppearances() throws {
        let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
        tile.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        tile.isSelected = true
        let light = try rgba(try XCTUnwrap(tile.previewOutlineColorForTesting))

        tile.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        tile.isSelected = false
        tile.isSelected = true
        let dark = try rgba(try XCTUnwrap(tile.previewOutlineColorForTesting))

        XCTAssertNotEqual(light.0, dark.0)
        XCTAssertNotEqual(light.2, dark.2)
        XCTAssertLessThan(light.2, dark.2, "Dark Mode receives the brighter blue")
    }

    func testUnavailableToLoadedTransitionKeepsCanvasBadgeAndSelectionGeometry() {
        let tile = configuredTile(imageSize: nil)
        tile.setPreviewUnavailable()
        tile.isSelected = true
        tile.layoutSubtreeIfNeeded()
        let canvas = tile.previewCanvasFrameForTesting
        let badge = tile.badgeFrameForTesting
        let width = tile.previewOutlineWidthForTesting

        tile.setPreview(NSImage(size: NSSize(width: 400, height: 100)), fadeIn: true)
        tile.layoutSubtreeIfNeeded()

        XCTAssertFalse(tile.showsUnavailableStateForTesting)
        XCTAssertEqual(tile.previewCanvasFrameForTesting, canvas)
        XCTAssertEqual(tile.badgeFrameForTesting, badge)
        XCTAssertEqual(tile.previewOutlineWidthForTesting, width)
    }

    func testCloseButtonCenterMatchesLoadedPreviewTopLeftPoint() {
        let tile = configuredTile(imageSize: NSSize(width: 400, height: 200))
        XCTAssertEqual(tile.closeFrameForTesting.midX,
                       tile.previewCanvasFrameForTesting.minX)
        XCTAssertEqual(tile.closeFrameForTesting.midY,
                       tile.previewCanvasFrameForTesting.maxY)
    }

    func testPanelUsesOneHorizontalSpacingAndNoSettingsChromeRow() throws {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
        let first = try XCTUnwrap(panel.tileFrameForTesting(at: 0))
        let second = try XCTUnwrap(panel.tileFrameForTesting(at: 1))

        XCTAssertEqual(second.minX - first.maxX, DesignTokens.tileSpacing)
        XCTAssertEqual(panel.panelBackgroundFrameForTesting.height,
                       panel.gridFrameForTesting.height
                           - DesignTokens.closeButtonTopOverflow
                           + DesignTokens.panelPadding * 2)
        XCTAssertEqual(panel.settingsButtonFrameForTesting.maxX,
                       panel.panelBackgroundFrameForTesting.maxX
                           + DesignTokens.chromeButtonOutsideOverlap)
        let close = try XCTUnwrap(panel.closeFrameForTesting(at: 0))
        XCTAssertTrue(panel.panelBackgroundFrameForTesting.contains(close),
                      "the existing panel padding must keep the complete Close control visible")
        XCTAssertEqual(panel.settingsButtonFrameForTesting.maxY,
                       panel.panelBackgroundFrameForTesting.maxY
                           + DesignTokens.chromeButtonOutsideOverlap)
        XCTAssertEqual(panel.frame.width,
                       panel.panelBackgroundFrameForTesting.width
                           + DesignTokens.chromeButtonOutsideOverlap)
        XCTAssertEqual(panel.frame.height,
                       panel.panelBackgroundFrameForTesting.height
                           + DesignTokens.chromeButtonOutsideOverlap)
    }

    func testWrappedRowsUseOneFullCardSpacing() throws {
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: (0..<100).map { item("\($0)") }, selectedIndex: 0)
        let columns = panel.columnsPerRow
        XCTAssertGreaterThan(columns, 0)
        XCTAssertLessThan(columns, 100)
        let firstRow = try XCTUnwrap(panel.tileFrameForTesting(at: 0))
        let secondRow = try XCTUnwrap(panel.tileFrameForTesting(at: columns))

        XCTAssertEqual(firstRow.minY - secondRow.maxY, DesignTokens.tileRowSpacing)
    }

    private func configuredTile(imageSize: NSSize?,
                                mode: AppearanceMode = .windowPreviews) -> SwitcherTileView {
        let tile = SwitcherTileView()
        tile.configure(item: item("tile"), mode: mode,
                       preview: imageSize.map(NSImage.init(size:)))
        tile.frame = NSRect(origin: .zero,
                            size: SwitcherTileView.Metrics.metrics(for: mode).tileSize)
        tile.layoutSubtreeIfNeeded()
        return tile
    }

    private func rgba(_ color: NSColor) throws -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    }

    private func item(_ id: String) -> SwitcherItem {
        SwitcherItem(id: id, window: nil, title: "Window \(id)",
                     appName: "TestApp", icon: nil, tabCount: nil)
    }
}
