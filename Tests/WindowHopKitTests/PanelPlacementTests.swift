import XCTest
@testable import WindowHopCore

final class PanelPlacementTests: XCTestCase {
    private func display(_ id: String,
                         width: CGFloat = 1920,
                         height: CGFloat = 1080,
                         scale: CGFloat = 2) -> DisplayDescriptor {
        DisplayDescriptor(id: id,
                          name: "Display \(id)",
                          visibleFrame: CGRect(x: 0, y: 0, width: width, height: height),
                          backingScale: scale)
    }

    private lazy var laptop = display("laptop")
    private lazy var external = display("external", width: 3840, height: 2160, scale: 1)
    private lazy var small = display("small", width: 1280, height: 800, scale: 2)

    // MARK: - Resolver

    func testAllDisplaysTargetsEveryConnectedDisplay() {
        let targets = PanelDisplayResolver.targets(
            placement: .allDisplays,
            chosenDisplayID: nil,
            available: [laptop, external],
            pointerDisplayID: laptop.id)

        XCTAssertEqual(targets, [laptop, external])
    }

    func testPointerDisplayTargetsOnlyTheDisplayHoldingThePointer() {
        let targets = PanelDisplayResolver.targets(
            placement: .pointerDisplay,
            chosenDisplayID: nil,
            available: [laptop, external],
            pointerDisplayID: external.id)

        XCTAssertEqual(targets, [external])
    }

    func testSpecificDisplayTargetsTheChosenDisplayRegardlessOfThePointer() {
        let targets = PanelDisplayResolver.targets(
            placement: .specificDisplay,
            chosenDisplayID: external.id,
            available: [laptop, external],
            pointerDisplayID: laptop.id)

        XCTAssertEqual(targets, [external])
    }

    func testDisconnectedChosenDisplayFallsBackToThePointerDisplay() {
        let targets = PanelDisplayResolver.targets(
            placement: .specificDisplay,
            chosenDisplayID: "unplugged",
            available: [laptop, external],
            pointerDisplayID: external.id)

        XCTAssertEqual(targets, [external],
                       "An unplugged monitor must not leave the switcher without a display")
    }

    func testReconnectingTheChosenDisplayRestoresItWithoutReconfiguration() {
        let stored = external.id
        let whileUnplugged = PanelDisplayResolver.targets(
            placement: .specificDisplay,
            chosenDisplayID: stored,
            available: [laptop],
            pointerDisplayID: laptop.id)
        let afterReconnect = PanelDisplayResolver.targets(
            placement: .specificDisplay,
            chosenDisplayID: stored,
            available: [laptop, external],
            pointerDisplayID: laptop.id)

        XCTAssertEqual(whileUnplugged, [laptop])
        XCTAssertEqual(afterReconnect, [external])
    }

    func testUnresolvablePointerStillProducesATarget() {
        let targets = PanelDisplayResolver.targets(
            placement: .pointerDisplay,
            chosenDisplayID: nil,
            available: [laptop, external],
            pointerDisplayID: nil)

        XCTAssertEqual(targets, [laptop])
    }

    func testNoConnectedDisplayResolvesToNoPanels() {
        for placement in SwitcherDisplayPlacement.allCases {
            XCTAssertTrue(PanelDisplayResolver.targets(
                placement: placement,
                chosenDisplayID: "anything",
                available: [],
                pointerDisplayID: "anything").isEmpty)
        }
    }

    func testEveryPlacementAlwaysYieldsADisplayWhenOneExists() {
        for placement in SwitcherDisplayPlacement.allCases {
            let targets = PanelDisplayResolver.targets(
                placement: placement,
                chosenDisplayID: nil,
                available: [laptop],
                pointerDisplayID: nil)
            XCTAssertFalse(targets.isEmpty,
                           "\(placement.rawValue) left the switcher with no display")
        }
    }

    // MARK: - Shared grid

    func testMostConstrainedExtentTakesTheNarrowestAndShortestIndependently() {
        // the narrowest and the shortest can be different displays; the shared
        // grid has to fit inside both
        let wideButShort = display("wide", width: 3840, height: 900)
        let narrowButTall = display("narrow", width: 1200, height: 2160)

        let extent = SwitcherGridCapacity.mostConstrainedExtent([wideButShort, narrowButTall])

        XCTAssertEqual(extent?.width, 1200)
        XCTAssertEqual(extent?.height, 900)
    }

    func testMostConstrainedExtentIsNilWithoutDisplays() {
        XCTAssertNil(SwitcherGridCapacity.mostConstrainedExtent([]))
    }

    func testColumnsNeverDropBelowOneOnATinyDisplay() {
        let columns = SwitcherGridCapacity.columns(
            visibleWidth: 200,
            tileWidth: 400,
            spacing: 12,
            padding: 16,
            maxWidthFraction: 0.9,
            tileCount: 8)

        XCTAssertEqual(columns, 1)
    }

    func testColumnsNeverExceedTheNumberOfTiles() {
        let columns = SwitcherGridCapacity.columns(
            visibleWidth: 6000,
            tileWidth: 200,
            spacing: 12,
            padding: 16,
            maxWidthFraction: 0.9,
            tileCount: 3)

        XCTAssertEqual(columns, 3)
    }

    func testTheSharedGridFitsTheMostConstrainedDisplay() {
        let displays = [external, small]
        let extent = try! XCTUnwrap(SwitcherGridCapacity.mostConstrainedExtent(displays))

        let shared = SwitcherGridCapacity.columns(
            visibleWidth: extent.width, tileWidth: 300, spacing: 12,
            padding: 16, maxWidthFraction: 0.9, tileCount: 20)
        let onSmallest = SwitcherGridCapacity.columns(
            visibleWidth: small.visibleFrame.width, tileWidth: 300, spacing: 12,
            padding: 16, maxWidthFraction: 0.9, tileCount: 20)
        let onLargest = SwitcherGridCapacity.columns(
            visibleWidth: external.visibleFrame.width, tileWidth: 300, spacing: 12,
            padding: 16, maxWidthFraction: 0.9, tileCount: 20)

        XCTAssertEqual(shared, onSmallest)
        XCTAssertLessThan(shared, onLargest,
                          "the shared grid is expected to cost the larger display columns")
    }

    func testRowsNeverDropBelowOne() {
        let rows = SwitcherGridCapacity.maxVisibleRows(
            visibleHeight: 100,
            tileHeight: 400,
            rowSpacing: 12,
            padding: 16,
            maxHeightFraction: 0.8)

        XCTAssertEqual(rows, 1)
    }

    // MARK: - Capture scale

    func testCaptureScaleTakesTheSharpestTargetSoRetinaIsNeverBlurred() {
        XCTAssertEqual(SwitcherGridCapacity.captureScale([external, laptop], fallback: 1), 2)
    }

    func testCaptureScaleFallsBackWithoutTargets() {
        XCTAssertEqual(SwitcherGridCapacity.captureScale([], fallback: 2), 2)
    }
}
