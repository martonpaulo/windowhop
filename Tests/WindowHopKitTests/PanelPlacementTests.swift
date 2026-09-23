import Foundation
import Testing

@testable import WindowHopKit

final class PanelPlacementTests {
    private func display(
        _ id: String,
        width: CGFloat = 1920,
        height: CGFloat = 1080,
        scale: CGFloat = 2
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            id: id,
            name: "Display \(id)",
            visibleFrame: CGRect(x: 0, y: 0, width: width, height: height),
            backingScale: scale)
    }

    private lazy var laptop = display("laptop")
    private lazy var external = display("external", width: 3840, height: 2160, scale: 1)
    private lazy var small = display("small", width: 1280, height: 800, scale: 2)

    // MARK: - Resolver

    @Test func allDisplaysTargetsEveryConnectedDisplay() {
        let targets = PanelDisplayResolver.targets(
            placement: .allDisplays,
            chosenDisplayID: nil,
            available: [laptop, external],
            pointerDisplayID: laptop.id)

        #expect(targets == [laptop, external])
    }

    @Test func pointerDisplayTargetsOnlyTheDisplayHoldingThePointer() {
        let targets = PanelDisplayResolver.targets(
            placement: .pointerDisplay,
            chosenDisplayID: nil,
            available: [laptop, external],
            pointerDisplayID: external.id)

        #expect(targets == [external])
    }

    @Test func specificDisplayTargetsTheChosenDisplayRegardlessOfThePointer() {
        let targets = PanelDisplayResolver.targets(
            placement: .specificDisplay,
            chosenDisplayID: external.id,
            available: [laptop, external],
            pointerDisplayID: laptop.id)

        #expect(targets == [external])
    }

    @Test func disconnectedChosenDisplayFallsBackToThePointerDisplay() {
        let targets = PanelDisplayResolver.targets(
            placement: .specificDisplay,
            chosenDisplayID: "unplugged",
            available: [laptop, external],
            pointerDisplayID: external.id)

        #expect(
            targets == [external],
            "An unplugged monitor must not leave the switcher without a display")
    }

    @Test func reconnectingTheChosenDisplayRestoresItWithoutReconfiguration() {
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

        #expect(whileUnplugged == [laptop])
        #expect(afterReconnect == [external])
    }

    @Test func unresolvablePointerStillProducesATarget() {
        let targets = PanelDisplayResolver.targets(
            placement: .pointerDisplay,
            chosenDisplayID: nil,
            available: [laptop, external],
            pointerDisplayID: nil)

        #expect(targets == [laptop])
    }

    @Test func noConnectedDisplayResolvesToNoPanels() {
        for placement in SwitcherDisplayPlacement.allCases {
            #expect(
                PanelDisplayResolver.targets(
                    placement: placement,
                    chosenDisplayID: "anything",
                    available: [],
                    pointerDisplayID: "anything"
                ).isEmpty)
        }
    }

    @Test func everyPlacementAlwaysYieldsADisplayWhenOneExists() {
        for placement in SwitcherDisplayPlacement.allCases {
            let targets = PanelDisplayResolver.targets(
                placement: placement,
                chosenDisplayID: nil,
                available: [laptop],
                pointerDisplayID: nil)
            #expect(
                !targets.isEmpty,
                "\(placement.rawValue) left the switcher with no display")
        }
    }

    // MARK: - Shared grid

    @Test func mostConstrainedExtentTakesTheNarrowestAndShortestIndependently() {
        // the narrowest and the shortest can be different displays; the shared
        // grid has to fit inside both
        let wideButShort = display("wide", width: 3840, height: 900)
        let narrowButTall = display("narrow", width: 1200, height: 2160)

        let extent = SwitcherGridCapacity.mostConstrainedExtent([wideButShort, narrowButTall])

        #expect(extent?.width == 1200)
        #expect(extent?.height == 900)
    }

    @Test func mostConstrainedExtentIsNilWithoutDisplays() {
        #expect(SwitcherGridCapacity.mostConstrainedExtent([]) == nil)
    }

    @Test func columnsNeverDropBelowOneOnATinyDisplay() {
        let columns = SwitcherGridCapacity.columns(
            visibleWidth: 200,
            tileWidth: 400,
            spacing: 12,
            padding: 16,
            maxWidthFraction: 0.9,
            tileCount: 8)

        #expect(columns == 1)
    }

    @Test func columnsNeverExceedTheNumberOfTiles() {
        let columns = SwitcherGridCapacity.columns(
            visibleWidth: 6000,
            tileWidth: 200,
            spacing: 12,
            padding: 16,
            maxWidthFraction: 0.9,
            tileCount: 3)

        #expect(columns == 3)
    }

    @Test func theSharedGridFitsTheMostConstrainedDisplay() throws {
        let displays = [external, small]
        let extent = try #require(SwitcherGridCapacity.mostConstrainedExtent(displays))

        let shared = SwitcherGridCapacity.columns(
            visibleWidth: extent.width, tileWidth: 300, spacing: 12,
            padding: 16, maxWidthFraction: 0.9, tileCount: 20)
        let onSmallest = SwitcherGridCapacity.columns(
            visibleWidth: small.visibleFrame.width, tileWidth: 300, spacing: 12,
            padding: 16, maxWidthFraction: 0.9, tileCount: 20)
        let onLargest = SwitcherGridCapacity.columns(
            visibleWidth: external.visibleFrame.width, tileWidth: 300, spacing: 12,
            padding: 16, maxWidthFraction: 0.9, tileCount: 20)

        #expect(shared == onSmallest)
        #expect(
            shared < onLargest,
            "the shared grid is expected to cost the larger display columns")
    }

    @Test func rowsNeverDropBelowOne() {
        let rows = SwitcherGridCapacity.maxVisibleRows(
            visibleHeight: 100,
            tileHeight: 400,
            rowSpacing: 12,
            padding: 16,
            maxHeightFraction: 0.8)

        #expect(rows == 1)
    }

    // MARK: - Capture scale

    @Test func captureScaleTakesTheSharpestTargetSoRetinaIsNeverBlurred() {
        #expect(SwitcherGridCapacity.captureScale([external, laptop], fallback: 1) == 2)
    }

    @Test func captureScaleFallsBackWithoutTargets() {
        #expect(SwitcherGridCapacity.captureScale([], fallback: 2) == 2)
    }
}
