import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// A list refresh during a session keeps every window on the tile that
    /// already shows it and reconfigures only tiles whose data changed (#119).
    /// A snapshot delivered straight to a tile (never in the provider cache in
    /// these tests) is the observable proof that a tile was not reconfigured.
    @MainActor
    final class SwitcherTileReuseTests {
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

        private func item(_ id: String, title: String? = nil) -> SwitcherItem {
            SwitcherItem(
                id: id, window: nil, title: title ?? "Window \(id)",
                appName: "TestApp", icon: nil, tabCount: nil)
        }

        private var image: NSImage { NSImage(size: NSSize(width: 40, height: 30)) }

        private func tile(_ panel: SwitcherPanel, _ index: Int) throws -> SwitcherTileView {
            try #require(panel.tileForTesting(at: index))
        }

        @Test func unchangedRefreshKeepsEveryTileAsItIs() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreview(id: "a", image: image)
            let first = try tile(panel, 0)

            panel.update(items: [item("a"), item("b")], selectedIndex: 0)

            #expect(try tile(panel, 0) === first)
            #expect(
                panel.tileShowsPreviewForTesting(at: 0),
                "an unchanged tile was reconfigured")
        }

        @Test func changedTitleReconfiguresOnlyThatTile() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreview(id: "a", image: image)

            panel.update(items: [item("a"), item("b", title: "Renamed")], selectedIndex: 0)

            #expect(panel.tileShowsPreviewForTesting(at: 0))
            #expect(try tile(panel, 1).accessibilityLabel() == "Renamed, TestApp")
        }

        @Test func reorderedWindowKeepsItsTileAndSnapshot() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreview(id: "b", image: image)
            let bTile = try tile(panel, 1)

            panel.update(items: [item("b"), item("a")], selectedIndex: 0)

            #expect(try tile(panel, 0) === bTile)
            #expect(panel.tileShowsPreviewForTesting(at: 0))
            #expect(!panel.tileShowsPreviewForTesting(at: 1))
        }

        @Test func appearanceChangeReconfiguresEveryTile() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a")], selectedIndex: 0)
            panel.updatePreview(id: "a", image: image)

            preferences.appearanceMode = .appIcons
            panel.update(items: [item("a")], selectedIndex: 0)

            #expect(!panel.tileShowsPreviewForTesting(at: 0))
        }

        @Test func aNewSessionReconfiguresTilesItAlreadyShowed() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.show(items: [item("a")], selectedIndex: 0, presentationMode: .persistent)
            panel.updatePreview(id: "a", image: image)
            panel.hide()

            panel.show(items: [item("a")], selectedIndex: 0, presentationMode: .persistent)
            panel.hide()

            // the provider cache holds nothing for "a", so a fresh configure
            // shows no snapshot; a skipped one would still show the old image
            #expect(!panel.tileShowsPreviewForTesting(at: 0))
        }

        @Test func clickReportsTheTilesCurrentPositionAfterItMoved() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            var clicked: [Int] = []
            var closeRequested: [Int] = []
            panel.onItemClicked = { clicked.append($0) }
            panel.onItemCloseRequested = { closeRequested.append($0) }
            panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
            let cTile = try tile(panel, 2)

            panel.update(items: [item("b"), item("c")], selectedIndex: 0)

            #expect(try tile(panel, 1) === cTile)
            #expect(cTile.accessibilityPerformPress())
            cTile.onCloseRequest?()
            #expect(clicked == [1])
            #expect(closeRequested == [1])
        }

        @Test func tileOrderFollowsItemOrderAfterANewWindowTakesAFreedSlot() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
            panel.update(items: [item("b"), item("c"), item("new")], selectedIndex: 0)

            let tiles = try (0..<3).map { try tile(panel, $0) }
            let container = try #require(tiles[0].superview)
            let visibleOrder = container.subviews.filter { !$0.isHidden }
            #expect(
                visibleOrder.elementsEqual(tiles, by: ===),
                "accessibility order must match the item order")
            #expect(try tile(panel, 2).accessibilityLabel() == "Window new, TestApp")
        }

        @Test func selectionChangeRestylesOnlyTheTilesItAffects() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
            for index in 0..<3 { try tile(panel, index).layoutSubtreeIfNeeded() }

            panel.select(1)

            #expect(try tile(panel, 0).needsLayout)
            #expect(try tile(panel, 1).needsLayout)
            #expect(
                try !tile(panel, 2).needsLayout,
                "an unaffected tile was restyled")
        }
    }
}
