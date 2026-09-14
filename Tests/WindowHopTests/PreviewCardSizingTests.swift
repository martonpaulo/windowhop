import XCTest
@testable import WindowHopCore

/// Window Previews cards follow the display and the Preview size setting
/// (issue #33): Medium fits four full rows in the panel height and Large three,
/// like AltTab's Medium and Large thumbnails; Small keeps the original card.
/// No size drops below the original card or below three cards per row.
final class PreviewCardSizingTests: XCTestCase {
    private let ultrawide = CGSize(width: 3440, height: 1415)
    private let laptop = CGSize(width: 1512, height: 920)
    private let portrait = CGSize(width: 1080, height: 1895)
    private let growingSizes: [PreviewSize] = [.medium, .large]

    private func width(_ extent: CGSize, _ size: PreviewSize = .medium) -> CGFloat {
        DesignTokens.previewContentWidth(visibleExtent: extent, size: size)
    }

    private func assertRowsFit(_ extent: CGSize, _ size: PreviewSize, showMetadata: Bool,
                               file: StaticString = #filePath, line: UInt = #line) {
        // the row budget binds only once a card grows; at the floor the original
        // card wins and the panel scrolls, exactly as before sizes existed
        guard let rowCount = size.rowsOnScreen,
              width(extent, size) > DesignTokens.previewMinimumContentWidth else { return }
        let layout = DesignTokens.previewCardSizing(rows: rowCount)
        let canvasHeight = DesignTokens.previewContentHeight(width: width(extent, size))
        let cardHeight = DesignTokens.tileHeight(contentHeight: canvasHeight,
                                                 showMetadata: showMetadata)
        let rows = CGFloat(rowCount)
        let used = rows * cardHeight + (rows - 1) * layout.rowSpacing
        let budget = extent.height * layout.maxHeightFraction - layout.padding * 2
        XCTAssertLessThanOrEqual(used, budget, "\(size) overflows \(extent)",
                                 file: file, line: line)
    }

    func testSizesMapToAltTabRowCounts() {
        XCTAssertEqual(Preferences.Defaults.previewSize, .medium)
        XCTAssertNil(PreviewSize.small.rowsOnScreen)
        XCTAssertEqual(PreviewSize.medium.rowsOnScreen, 4)
        XCTAssertEqual(PreviewSize.large.rowsOnScreen, 3)
        XCTAssertEqual(PreviewSize.allCases.map(\.displayName), ["Small", "Medium", "Large"])
    }

    func testUltrawideSizes() {
        XCTAssertEqual(width(ultrawide, .small), 188)
        XCTAssertEqual(width(ultrawide, .medium), 302)
        XCTAssertEqual(DesignTokens.previewContentHeight(width: 302), 189)
        XCTAssertEqual(width(ultrawide, .large), 462)
        XCTAssertEqual(DesignTokens.previewContentHeight(width: 462), 289)
    }

    func testRowsFitWithAndWithoutTabCounts() {
        for extent in [ultrawide, laptop, portrait] {
            for size in growingSizes {
                assertRowsFit(extent, size, showMetadata: true)
                assertRowsFit(extent, size, showMetadata: false)
            }
        }
    }

    func testTabCountsNeverResizeThePreviews() {
        for extent in [ultrawide, laptop, portrait] {
            for size in PreviewSize.allCases {
                XCTAssertEqual(
                    SwitcherTileView.Metrics.windowPreviews(
                        showTabCounts: true, visibleExtent: extent, size: size).contentSize.width,
                    SwitcherTileView.Metrics.windowPreviews(
                        showTabCounts: false, visibleExtent: extent, size: size).contentSize.width)
            }
        }
    }

    func testLaptopsKeepTheOriginalCardAtMediumAndGrowAtLarge() {
        XCTAssertEqual(width(laptop, .medium), 188)
        XCTAssertEqual(width(laptop, .large), 238)
    }

    func testPortraitDisplaysKeepThreeCardsPerRow() {
        let layout = DesignTokens.previewCardSizing(rows: 4)
        for size in growingSizes {
            let cardWidth = width(portrait, size) + layout.cardChromeWidth
            let used = CGFloat(layout.minimumColumns) * cardWidth
                + CGFloat(layout.minimumColumns - 1) * layout.spacing
            XCTAssertEqual(width(portrait, size), 278)
            XCTAssertLessThanOrEqual(
                used, portrait.width * layout.maxWidthFraction - layout.padding * 2)
        }
    }

    func testSmallAndOffscreenAlwaysUseTheOriginalCard() {
        for size in PreviewSize.allCases {
            XCTAssertEqual(width(CGSize(width: 800, height: 600), size), 188)
            XCTAssertEqual(DesignTokens.previewContentWidth(visibleExtent: nil, size: size), 188)
        }
        XCTAssertEqual(DesignTokens.previewContentHeight(width: 188), 118)
    }

    func testScaledCanvasKeepsTheFixedSixteenByTenShape() {
        for extent in [ultrawide, laptop, portrait] {
            for size in PreviewSize.allCases {
                let canvasWidth = width(extent, size)
                XCTAssertEqual(DesignTokens.previewContentHeight(width: canvasWidth),
                               (canvasWidth / DesignTokens.previewCanvasAspect).rounded())
            }
        }
    }

    func testTheAppIconScalesWithTheCanvas() {
        XCTAssertEqual(DesignTokens.scaledPreviewBadgeSize(canvasWidth: 188), 48)
        XCTAssertEqual(DesignTokens.scaledPreviewOverlayOverlap(canvasWidth: 188), 8)
        XCTAssertEqual(DesignTokens.scaledPreviewBadgeSize(canvasWidth: 302), 77)
        XCTAssertEqual(DesignTokens.scaledPreviewOverlayOverlap(canvasWidth: 302), 13)
        XCTAssertEqual(DesignTokens.scaledPreviewBadgeSize(canvasWidth: 462), 118)
    }

    func testTheRuleIsIndependentOfTokens() {
        let layout = PreviewCardSizing.Layout(
            rows: 2, minimumColumns: 1, minimumCanvasWidth: 10, canvasAspect: 2,
            cardChromeHeight: 0, cardChromeWidth: 0, spacing: 0, rowSpacing: 0, padding: 0,
            maxWidthFraction: 1, maxHeightFraction: 1)
        // two rows of 100 pt cards; a 2:1 canvas is then 200 pt wide
        XCTAssertEqual(PreviewCardSizing.canvasWidth(
            visibleExtent: CGSize(width: 1000, height: 200), layout: layout), 200)
        // the width budget wins when it is tighter
        XCTAssertEqual(PreviewCardSizing.canvasWidth(
            visibleExtent: CGSize(width: 150, height: 200), layout: layout), 150)
    }
}
