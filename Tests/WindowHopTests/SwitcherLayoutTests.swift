import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    @MainActor
    final class SwitcherLayoutTests {
        private var isolated: IsolatedPreferences!
        private var preferences: Preferences { isolated.preferences }
        private var previews: PreviewProvider { isolated.previews }

        init() throws {
            isolated = try IsolatedPreferences()
            preferences.appearanceMode = .windowPreviews
        }

        isolated deinit {
            isolated.remove()
            isolated = nil
        }

        // MARK: - Preview canvas geometry (issue #13)

        /// The canvas is fixed at 16:10 regardless of the monitor. Deriving it from
        /// the display turned every card into a shallow strip on an ultrawide
        /// screen, which is exactly where previews are hardest to recognize.
        @Test func previewCanvasIsFixedAtSixteenByTen() {
            let contentWidth = DesignTokens.previewsTileWidth - DesignTokens.tileLabelInset * 2

            #expect(DesignTokens.previewContentHeight(width: contentWidth) == 118)
            #expect(DesignTokens.previewCanvasAspect == CGFloat(16.0) / 10.0)
        }

        /// The same rule, at the real configured-tile seam.
        @Test func configuredTileUsesTheFixedCanvasHeight() {
            let tile = configuredTile(imageSize: NSSize(width: 3440, height: 1440))

            #expect(tile.previewCanvasFrameForTesting.height == 118)
            #expect(tile.previewCanvasFrameForTesting.width == 188)
        }

        /// A snapshot smaller than the canvas, such as a half-size capture from
        /// a 1x display, is scaled up to fill it, never left in its middle (#33).
        @Test func aSmallSnapshotFillsTheCanvas() {
            let tile = configuredTile(imageSize: NSSize(width: 94, height: 59))
            let canvas = tile.previewCanvasFrameForTesting
            let image = tile.previewImageFrameForTesting

            #expect(abs(image.width - canvas.width) <= 1)
            #expect(abs(image.midY - canvas.midY) < 0.5)
        }

        /// Source images of any shape cover the canvas, and the canvas's rounded
        /// clip, not the image, bounds what is drawn (#127).
        @Test func everySourceCoversTheCanvasAndIsClippedByIt() {
            for size in [
                NSSize(width: 3440, height: 1440), NSSize(width: 100, height: 900),
                NSSize(width: 4, height: 4), NSSize(width: 1, height: 1),
            ] {
                let tile = configuredTile(imageSize: size)
                let canvas = tile.previewCanvasFrameForTesting
                let image = tile.previewImageFrameForTesting

                // a whole-pixel tolerance: proportional scaling lands on fractions
                #expect(
                    image.insetBy(dx: -1, dy: -1).contains(canvas),
                    "\(size) leaves part of the canvas empty")
                #expect(tile.previewClipFrameForTesting == canvas)
            }
        }

        /// The regression: centring a 309-pixel-tall capture in the 118-point canvas
        /// put it at y = -95.5, and on a 1x display every row was then blended with
        /// its neighbour, so a sharp capture drew blurred (#130). Measured on screen
        /// with one-pixel stripes: rows of 0.57 grey before, 1.0 and 0.0 after.
        @Test(arguments: [NSSize(width: 188, height: 309), NSSize(width: 451, height: 118)])
        func aCaptureAtTheCanvasScaleIsDrawnOnWholePixels(pixels: NSSize) {
            let tile = configuredTile(imageSize: pixels)
            let image = tile.previewImageFrameForTesting

            #expect(image.origin.x == image.origin.x.rounded())
            #expect(image.origin.y == image.origin.y.rounded())
            #expect(image.size == pixels)
        }

        @Test func overlaysStayCanvasAlignedAcrossSourceAspectRatios() {
            let wide = configuredTile(imageSize: NSSize(width: 400, height: 100))
            let tall = configuredTile(imageSize: NSSize(width: 100, height: 400))

            #expect(wide.previewCanvasFrameForTesting == tall.previewCanvasFrameForTesting)
            #expect(wide.badgeFrameForTesting == tall.badgeFrameForTesting)
            #expect(wide.closeFrameForTesting == tall.closeFrameForTesting)
            #expect(wide.previewImageFrameForTesting != tall.previewImageFrameForTesting)
            #expect(
                wide.badgeFrameForTesting.maxX == wide.previewCanvasFrameForTesting.maxX
                    + DesignTokens.previewOverlayOverlap)
            #expect(
                wide.badgeFrameForTesting.minY == wide.previewCanvasFrameForTesting.minY
                    - DesignTokens.previewOverlayOverlap)
            #expect(wide.badgeFrameForTesting.maxX <= wide.bounds.maxX)
            #expect(wide.badgeFrameForTesting.minY >= wide.bounds.minY)

            let loading = configuredTile(imageSize: nil)
            #expect(loading.showsLoadingStateForTesting)
            #expect(loading.previewCanvasFrameForTesting == wide.previewCanvasFrameForTesting)
            #expect(loading.badgeFrameForTesting == wide.badgeFrameForTesting)
        }

        @Test func everyPreviewStateUsesTheSameSingleSelectionBackground() throws {
            let loaded = configuredTile(imageSize: NSSize(width: 300, height: 200))
            let loading = configuredTile(imageSize: nil)
            let unavailable = configuredTile(imageSize: nil)
            unavailable.setPreviewPresentation(.captureUnavailable)
            unavailable.layoutSubtreeIfNeeded()
            let permissionUnavailable = configuredTile(imageSize: nil)
            permissionUnavailable.setPreviewPresentation(.permissionUnavailable)
            permissionUnavailable.layoutSubtreeIfNeeded()

            for tile in [loaded, loading, unavailable, permissionUnavailable] {
                tile.isSelected = true
                tile.layoutSubtreeIfNeeded()
                #expect(borderedLayers(in: tile).isEmpty)
                #expect(
                    tile.selectionBackgroundFrameForTesting == loaded.selectionBackgroundFrameForTesting)
                #expect(
                    abs(tile.selectionBackgroundAlphaForTesting - DesignTokens.previewSelectionFill.alphaComponent)
                        <= 0.001)
            }
            #expect(
                try abs(
                    rgba(try #require(loaded.selectionBackgroundColorForTesting)).3
                        - (try rgba(try #require(permissionUnavailable.selectionBackgroundColorForTesting)).3)) <= 0.001
            )
            #expect(unavailable.showsUnavailableStateForTesting)
            #expect(permissionUnavailable.showsPermissionUnavailableStateForTesting)
        }

        @Test func iconOnlyCardsUseBackgroundSelectionWithoutAnyOutline() {
            let tile = configuredTile(imageSize: nil, mode: .appIcons)

            #expect(borderedLayers(in: tile).isEmpty)
            #expect(tile.selectionBackgroundAlphaForTesting == 0)
            tile.isSelected = true
            #expect(borderedLayers(in: tile).isEmpty)
            #expect(
                tile.selectionBackgroundAlphaForTesting == DesignTokens.iconSelectionFill.alphaComponent)
        }

        @Test func unselectedPreviewHasSurfaceButNoPermanentSelectionFrame() {
            let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
            #expect(borderedLayers(in: tile).isEmpty)
            #expect(tile.selectionBackgroundAlphaForTesting == 0)
            #expect(tile.previewSurfaceColorForTesting != nil)

            tile.isSelected = true
            #expect(borderedLayers(in: tile).isEmpty)
            #expect(tile.selectionBackgroundAlphaForTesting > 0)
        }

        @Test func selectionUsesSemanticSystemFocusColorInBothAppearances() throws {
            let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
            let aqua = try #require(NSAppearance(named: .aqua))
            tile.appearance = aqua
            tile.isSelected = true
            let light = try rgba(try #require(tile.selectionBackgroundColorForTesting))

            let darkAqua = try #require(NSAppearance(named: .darkAqua))
            tile.appearance = darkAqua
            tile.isSelected = false
            tile.isSelected = true
            let dark = try rgba(try #require(tile.selectionBackgroundColorForTesting))

            #expect(
                abs(light.3 - DesignTokens.previewSelectionFill.alphaComponent) <= 0.001)
            #expect(
                abs(dark.3 - DesignTokens.previewSelectionFill.alphaComponent) <= 0.001)
            #expect(light.0 + light.1 + light.2 > 0)
            #expect(dark.0 + dark.1 + dark.2 > 0)
        }

        @Test func unavailableToLoadedTransitionKeepsCanvasBadgeAndSelectionGeometry() {
            let tile = configuredTile(imageSize: nil)
            tile.setPreviewPresentation(.captureUnavailable)
            tile.isSelected = true
            tile.layoutSubtreeIfNeeded()
            let canvas = tile.previewCanvasFrameForTesting
            let badge = tile.badgeFrameForTesting
            let selectionFrame = tile.selectionBackgroundFrameForTesting

            tile.setPreview(NSImage(size: NSSize(width: 400, height: 100)), fadeIn: true)
            tile.layoutSubtreeIfNeeded()

            #expect(!tile.showsUnavailableStateForTesting)
            #expect(tile.previewCanvasFrameForTesting == canvas)
            #expect(tile.badgeFrameForTesting == badge)
            #expect(tile.selectionBackgroundFrameForTesting == selectionFrame)
        }

        @Test func closeButtonCenterMatchesLoadedPreviewTopLeftPoint() {
            let tile = configuredTile(imageSize: NSSize(width: 400, height: 200))
            #expect(
                tile.closeFrameForTesting.midX == tile.previewCanvasFrameForTesting.minX)
            #expect(
                tile.closeFrameForTesting.midY == tile.previewCanvasFrameForTesting.maxY)
        }

        @Test func panelUsesOneHorizontalSpacingAndNoSettingsChromeRow() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
            let first = try #require(panel.tileFrameForTesting(at: 0))
            let second = try #require(panel.tileFrameForTesting(at: 1))

            #expect(second.minX - first.maxX == DesignTokens.tileSpacing)
            #expect(
                panel.panelBackgroundFrameForTesting.height == panel.gridFrameForTesting.height
                    - DesignTokens.closeButtonTopOverflow
                    + DesignTokens.panelPadding * 2)
            #expect(
                panel.settingsButtonFrameForTesting.maxX == panel.panelBackgroundFrameForTesting.maxX
                    + DesignTokens.chromeButtonOutsideOverlap)
            let close = try #require(panel.closeFrameForTesting(at: 0))
            #expect(
                panel.panelBackgroundFrameForTesting.contains(close),
                "the existing panel padding must keep the complete Close control visible")
            #expect(
                panel.settingsButtonFrameForTesting.maxY == panel.panelBackgroundFrameForTesting.maxY
                    + DesignTokens.chromeButtonOutsideOverlap)
            #expect(
                panel.frame.width == panel.panelBackgroundFrameForTesting.width
                    + DesignTokens.chromeButtonOutsideOverlap)
            #expect(
                panel.frame.height == panel.panelBackgroundFrameForTesting.height
                    + DesignTokens.chromeButtonOutsideOverlap)
        }

        @Test func settingsButtonIsContextualInCyclingAndPersistentModes() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            let items = [item("a")]

            panel.show(items: items, selectedIndex: 0, presentationMode: .cycling)
            // showing seeds hover from the real pointer, which on a machine in use can
            // already sit over the panel; the contextual rule is what is under test
            panel.setPanelHoverForTesting(false)
            #expect(!panel.settingsButtonIsVisibleForTesting)
            panel.setPanelHoverForTesting(true)
            #expect(panel.settingsButtonIsVisibleForTesting)
            panel.setPanelHoverForTesting(false)
            #expect(!panel.settingsButtonIsVisibleForTesting)

            panel.show(items: items, selectedIndex: 0, presentationMode: .persistent)
            #expect(panel.settingsButtonIsVisibleForTesting)
            panel.setPanelHoverForTesting(false)
            #expect(panel.settingsButtonIsVisibleForTesting)
        }

        @Test func hidingMetadataCompactsCardAndPanelWithoutChangingPreviewWidth() throws {
            let saved = preferences.showTabCounts
            defer { preferences.showTabCounts = saved }
            preferences.showTabCounts = true
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a")], selectedIndex: 0)
            let visibleFrame = try #require(panel.tileFrameForTesting(at: 0))
            let visibleCanvas = try #require(panel.tileForTesting(at: 0))
                .previewCanvasFrameForTesting
            let visiblePanelHeight = panel.panelBackgroundFrameForTesting.height

            preferences.showTabCounts = false
            panel.update(items: [item("a")], selectedIndex: 0)
            let hiddenFrame = try #require(panel.tileFrameForTesting(at: 0))
            let hiddenTile = try #require(panel.tileForTesting(at: 0))

            #expect(hiddenFrame.width == visibleFrame.width)
            #expect(hiddenFrame.height < visibleFrame.height)
            #expect(hiddenTile.previewCanvasFrameForTesting.width == visibleCanvas.width)
            #expect(hiddenTile.metadataIsHiddenForTesting)
            #expect(panel.panelBackgroundFrameForTesting.height < visiblePanelHeight)
        }

        @Test func skeletonStatesAreExplicitAndUnavailableNeverAnimates() {
            let loading = configuredTile(imageSize: nil)
            #expect(loading.showsLoadingStateForTesting)

            loading.setPreviewPresentation(.permissionUnavailable)
            #expect(loading.showsPermissionUnavailableStateForTesting)
            #expect(!loading.skeletonIsAnimatingForTesting)

            loading.setPreviewPresentation(.loading)
            loading.setPreviewPresentation(.captureUnavailable)
            #expect(loading.showsUnavailableStateForTesting)
            #expect(!loading.skeletonIsAnimatingForTesting)
        }

        @Test(
            .disabled(
                if: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "Reduce Motion is on, so no skeleton ever pulses"))
        func appIconsTilesNeverPulseTheirHiddenSkeleton() throws {
            preferences.appearanceMode = .appIcons
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a")], selectedIndex: 0)
            let tile = try #require(panel.tileForTesting(at: 0))
            #expect(
                !tile.skeletonIsAnimatingForTesting,
                "an App Icons tile animated a skeleton nobody sees")

            preferences.appearanceMode = .windowPreviews
            panel.update(items: [item("a")], selectedIndex: 0)
            #expect(tile.skeletonIsAnimatingForTesting, "a visible loading preview pulses")
        }

        @Test(
            .disabled(
                if: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "Reduce Motion is on, so no skeleton ever pulses"))
        func pulseFollowsTileVisibility() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            let slot = try #require(panel.tileForTesting(at: 1))
            #expect(slot.skeletonIsAnimatingForTesting)

            slot.isHidden = true
            #expect(!slot.skeletonIsAnimatingForTesting, "a hidden tile kept pulsing")
            slot.isHidden = false
            #expect(slot.skeletonIsAnimatingForTesting, "unhiding a loading tile restores it")

            panel.update(items: [item("a")], selectedIndex: 0)
            #expect(!slot.skeletonIsAnimatingForTesting)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            #expect(slot.skeletonIsAnimatingForTesting, "a reused slot pulses again")
        }

        @Test func sharedTypographyUsesNativeSystemHierarchy() throws {
            let tile = configuredTile(imageSize: NSSize(width: 300, height: 200))
            let title = try #require(tile.titleFontForTesting)
            let metadata = try #require(tile.metadataFontForTesting)

            #expect(title.familyName == NSFont.systemFont(ofSize: 14).familyName)
            #expect(metadata.familyName == NSFont.systemFont(ofSize: 12).familyName)
            #expect(title.pointSize > metadata.pointSize)
            #expect(title.pointSize == DesignTokens.titleFontSize)
            #expect(metadata.pointSize == DesignTokens.metadataFontSize)
        }

        @Test func wrappedRowsUseOneFullCardSpacing() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: (0..<100).map { item("\($0)") }, selectedIndex: 0)
            let columns = panel.columnsPerRow
            #expect(columns > 0)
            #expect(columns < 100)
            let firstRow = try #require(panel.tileFrameForTesting(at: 0))
            let secondRow = try #require(panel.tileFrameForTesting(at: columns))

            #expect(firstRow.minY - secondRow.maxY == DesignTokens.tileRowSpacing)
        }

        private func configuredTile(
            imageSize: NSSize?,
            mode: AppearanceMode = .windowPreviews
        ) -> SwitcherTileView {
            let tile = SwitcherTileView()
            tile.configure(
                item: item("tile"), mode: mode, showTabCounts: false,
                preview: imageSize.map(NSImage.init(size:)))
            tile.frame = NSRect(
                origin: .zero,
                size: SwitcherTileView.Metrics.metrics(
                    for: mode, showTabCounts: false
                ).tileSize)
            tile.layoutSubtreeIfNeeded()
            return tile
        }

        /// Every visible layer in the tile's rendered tree that draws a border.
        /// Selection is a background fill only; any border here is an outline.
        private func borderedLayers(in view: NSView) -> [CALayer] {
            guard !view.isHidden else { return [] }
            var found: [CALayer] = []
            if let layer = view.layer {
                found += borderedLayers(in: layer)
            }
            for subview in view.subviews {
                found += borderedLayers(in: subview)
            }
            return found
        }

        private func borderedLayers(in layer: CALayer) -> [CALayer] {
            guard !layer.isHidden else { return [] }
            var found: [CALayer] = []
            if layer.borderWidth > 0, (layer.borderColor?.alpha ?? 0) > 0 {
                found.append(layer)
            }
            for sublayer in layer.sublayers ?? [] {
                found += borderedLayers(in: sublayer)
            }
            return found
        }

        private func rgba(_ color: NSColor) throws -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let rgb = try #require(color.usingColorSpace(.deviceRGB))
            return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        }

        private func item(_ id: String) -> SwitcherItem {
            SwitcherItem(
                id: id, window: nil, title: "Window \(id)",
                appName: "TestApp", icon: nil, tabCount: nil)
        }
    }
}
