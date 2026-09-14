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

    // MARK: - Preview canvas geometry (issue #13)

    /// The canvas is fixed at 16:10 regardless of the monitor. Deriving it from
    /// the display turned every card into a shallow strip on an ultrawide
    /// screen, which is exactly where previews are hardest to recognize.
    func testPreviewCanvasIsFixedAtSixteenByTen() {
        let contentWidth = DesignTokens.previewsTileWidth - DesignTokens.tileLabelInset * 2

        XCTAssertEqual(DesignTokens.previewContentHeight(width: contentWidth), 118)
        XCTAssertEqual(DesignTokens.previewCanvasAspect, 16.0 / 10.0)
    }

    /// The same rule, at the real configured-tile seam.
    func testConfiguredTileUsesTheFixedCanvasHeight() {
        let tile = configuredTile(imageSize: NSSize(width: 3440, height: 1440))

        XCTAssertEqual(tile.previewCanvasFrameForTesting.height, 118)
        XCTAssertEqual(tile.previewCanvasFrameForTesting.width, 188)
    }

    /// Source images of any shape stay inside that canvas without cropping.
    func testEverySourceAspectFitsInsideTheCanvas() {
        for size in [NSSize(width: 3440, height: 1440), NSSize(width: 100, height: 900),
                     NSSize(width: 4, height: 4), NSSize(width: 1, height: 1)] {
            let tile = configuredTile(imageSize: size)
            let canvas = tile.previewCanvasFrameForTesting
            let image = tile.previewImageFrameForTesting

            // a whole-pixel tolerance: proportional scaling lands on fractions
            XCTAssertTrue(canvas.insetBy(dx: -1, dy: -1).contains(image),
                          "\(size) overflows the canvas")
            XCTAssertLessThanOrEqual(image.width, canvas.width + 1)
            XCTAssertLessThanOrEqual(image.height, canvas.height + 1)
        }
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

    func testEveryPreviewStateUsesTheSameSingleSelectionBackground() throws {
        let loaded = configuredTile(imageSize: NSSize(width: 300, height: 200))
        let loading = configuredTile(imageSize: nil)
        let unavailable = configuredTile(imageSize: nil)
        unavailable.setPreviewUnavailable()
        unavailable.layoutSubtreeIfNeeded()
        let permissionUnavailable = configuredTile(imageSize: nil)
        permissionUnavailable.setPreviewPermissionUnavailable()
        permissionUnavailable.layoutSubtreeIfNeeded()

        for tile in [loaded, loading, unavailable, permissionUnavailable] {
            tile.isSelected = true
            tile.layoutSubtreeIfNeeded()
            XCTAssertFalse(tile.showsCardOutlineForTesting)
            XCTAssertEqual(tile.selectionBackgroundFrameForTesting,
                           loaded.selectionBackgroundFrameForTesting)
            XCTAssertEqual(tile.selectionBackgroundAlphaForTesting,
                           DesignTokens.previewSelectionFill.alphaComponent,
                           accuracy: 0.001)
        }
        XCTAssertEqual(try rgba(try XCTUnwrap(loaded.selectionBackgroundColorForTesting)).3,
                       try rgba(try XCTUnwrap(permissionUnavailable.selectionBackgroundColorForTesting)).3,
                       accuracy: 0.001)
        XCTAssertTrue(unavailable.showsUnavailableStateForTesting)
        XCTAssertTrue(permissionUnavailable.showsPermissionUnavailableStateForTesting)
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

    func testUnselectedPreviewHasSurfaceButNoPermanentSelectionFrame() {
        let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
        XCTAssertFalse(tile.showsCardOutlineForTesting)
        XCTAssertEqual(tile.selectionBackgroundAlphaForTesting, 0)
        XCTAssertNotNil(tile.previewSurfaceColorForTesting)

        tile.isSelected = true
        XCTAssertFalse(tile.showsCardOutlineForTesting)
        XCTAssertGreaterThan(tile.selectionBackgroundAlphaForTesting, 0)
    }

    func testSelectionUsesSemanticSystemFocusColorInBothAppearances() throws {
        let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
        tile.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        tile.isSelected = true
        let light = try rgba(try XCTUnwrap(tile.selectionBackgroundColorForTesting))

        tile.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        tile.isSelected = false
        tile.isSelected = true
        let dark = try rgba(try XCTUnwrap(tile.selectionBackgroundColorForTesting))

        XCTAssertEqual(light.3, DesignTokens.previewSelectionFill.alphaComponent,
                       accuracy: 0.001)
        XCTAssertEqual(dark.3, DesignTokens.previewSelectionFill.alphaComponent,
                       accuracy: 0.001)
        XCTAssertGreaterThan(light.0 + light.1 + light.2, 0)
        XCTAssertGreaterThan(dark.0 + dark.1 + dark.2, 0)
    }

    func testUnavailableToLoadedTransitionKeepsCanvasBadgeAndSelectionGeometry() {
        let tile = configuredTile(imageSize: nil)
        tile.setPreviewUnavailable()
        tile.isSelected = true
        tile.layoutSubtreeIfNeeded()
        let canvas = tile.previewCanvasFrameForTesting
        let badge = tile.badgeFrameForTesting
        let selectionFrame = tile.selectionBackgroundFrameForTesting

        tile.setPreview(NSImage(size: NSSize(width: 400, height: 100)), fadeIn: true)
        tile.layoutSubtreeIfNeeded()

        XCTAssertFalse(tile.showsUnavailableStateForTesting)
        XCTAssertEqual(tile.previewCanvasFrameForTesting, canvas)
        XCTAssertEqual(tile.badgeFrameForTesting, badge)
        XCTAssertEqual(tile.selectionBackgroundFrameForTesting, selectionFrame)
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

    func testSettingsButtonIsContextualInCyclingAndPersistentModes() {
        let panel = SwitcherPanel(rasterizableBackground: true)
        let items = [item("a")]

        panel.show(items: items, selectedIndex: 0, presentationMode: .cycling)
        // showing seeds hover from the real pointer, which on a machine in use can
        // already sit over the panel; the contextual rule is what is under test
        panel.setPanelHoverForTesting(false)
        XCTAssertFalse(panel.settingsButtonIsVisibleForTesting)
        panel.setPanelHoverForTesting(true)
        XCTAssertTrue(panel.settingsButtonIsVisibleForTesting)
        panel.setPanelHoverForTesting(false)
        XCTAssertFalse(panel.settingsButtonIsVisibleForTesting)

        panel.show(items: items, selectedIndex: 0, presentationMode: .persistent)
        XCTAssertTrue(panel.settingsButtonIsVisibleForTesting)
        panel.setPanelHoverForTesting(false)
        XCTAssertTrue(panel.settingsButtonIsVisibleForTesting)
    }

    func testHidingMetadataCompactsCardAndPanelWithoutChangingPreviewWidth() throws {
        let saved = Preferences.shared.showTabCounts
        defer { Preferences.shared.showTabCounts = saved }
        Preferences.shared.showTabCounts = true
        let panel = SwitcherPanel(rasterizableBackground: true)
        panel.update(items: [item("a")], selectedIndex: 0)
        let visibleFrame = try XCTUnwrap(panel.tileFrameForTesting(at: 0))
        let visibleCanvas = try XCTUnwrap(panel.tileForTesting(at: 0))
            .previewCanvasFrameForTesting
        let visiblePanelHeight = panel.panelBackgroundFrameForTesting.height

        Preferences.shared.showTabCounts = false
        panel.update(items: [item("a")], selectedIndex: 0)
        let hiddenFrame = try XCTUnwrap(panel.tileFrameForTesting(at: 0))
        let hiddenTile = try XCTUnwrap(panel.tileForTesting(at: 0))

        XCTAssertEqual(hiddenFrame.width, visibleFrame.width)
        XCTAssertLessThan(hiddenFrame.height, visibleFrame.height)
        XCTAssertEqual(hiddenTile.previewCanvasFrameForTesting.width, visibleCanvas.width)
        XCTAssertTrue(hiddenTile.metadataIsHiddenForTesting)
        XCTAssertLessThan(panel.panelBackgroundFrameForTesting.height, visiblePanelHeight)
    }

    func testSkeletonStatesAreExplicitAndUnavailableNeverAnimates() {
        let loading = configuredTile(imageSize: nil)
        XCTAssertTrue(loading.showsLoadingStateForTesting)

        loading.setPreviewPermissionUnavailable()
        XCTAssertTrue(loading.showsPermissionUnavailableStateForTesting)
        XCTAssertFalse(loading.skeletonIsAnimatingForTesting)

        loading.setPreviewLoading()
        loading.setPreviewUnavailable()
        XCTAssertTrue(loading.showsUnavailableStateForTesting)
        XCTAssertFalse(loading.skeletonIsAnimatingForTesting)
    }

    func testSharedTypographyUsesNativeSystemHierarchy() throws {
        let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
        let title = try XCTUnwrap(tile.titleFontForTesting)
        let metadata = try XCTUnwrap(tile.metadataFontForTesting)

        XCTAssertEqual(title.familyName, NSFont.systemFont(ofSize: 14).familyName)
        XCTAssertEqual(metadata.familyName, NSFont.systemFont(ofSize: 12).familyName)
        XCTAssertGreaterThan(title.pointSize, metadata.pointSize)
        XCTAssertEqual(title.pointSize, DesignTokens.titleFontSize)
        XCTAssertEqual(metadata.pointSize, DesignTokens.metadataFontSize)
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
        tile.configure(item: item("tile"), mode: mode, showTabCounts: false,
                       preview: imageSize.map(NSImage.init(size:)))
        tile.frame = NSRect(origin: .zero,
                            size: SwitcherTileView.Metrics.metrics(
                                for: mode, showTabCounts: false).tileSize)
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
