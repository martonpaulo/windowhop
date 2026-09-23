import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// Preview/window association at the view layer: deliveries are keyed by the
    /// window's stable id, pooled tiles reset stale image state when they start
    /// representing another window, and rapid list changes can never move a
    /// snapshot onto a different card.
    @MainActor
    final class PreviewAssociationTests {
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

        private func item(_ id: String) -> SwitcherItem {
            SwitcherItem(
                id: id, window: nil, title: "Window \(id)",
                appName: "TestApp", icon: nil, tabCount: nil)
        }

        private var image: NSImage { NSImage(size: NSSize(width: 40, height: 30)) }

        @Test func reusedTileResetsStaleImageState() {
            let tile = SwitcherTileView()
            tile.configure(
                item: item("a"), mode: .windowPreviews,
                showTabCounts: false, preview: image)
            #expect(tile.showsPreviewImage)
            // the pooled tile now represents a window with no snapshot: nothing of
            // the previous occupant may remain visible
            tile.configure(
                item: item("b"), mode: .windowPreviews,
                showTabCounts: false, preview: nil)
            #expect(!tile.showsPreviewImage)
        }

        @Test func deliveryIsKeyedByWindowIdNotTilePosition() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreview(id: "b", image: image)
            #expect(!panel.tileShowsPreviewForTesting(at: 0))
            #expect(panel.tileShowsPreviewForTesting(at: 1))
        }

        @Test func reorderingNeverMovesASnapshotToAnotherCard() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreview(id: "b", image: image)
            // the tile that showed b's snapshot now represents a — it must not
            // keep the old image (there is no cached snapshot for either window)
            panel.update(items: [item("b"), item("a")], selectedIndex: 0)
            #expect(!panel.tileShowsPreviewForTesting(at: 1))
        }

        @Test func deliveryForARemovedWindowIsIgnored() {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b"), item("c")], selectedIndex: 0)
            panel.updatePreview(id: "b", image: image)
            // b closes mid-session; a late capture for it must go nowhere
            panel.update(items: [item("a"), item("c")], selectedIndex: 0)
            panel.updatePreview(id: "b", image: image)
            #expect(!panel.tileShowsPreviewForTesting(at: 0))
            #expect(!panel.tileShowsPreviewForTesting(at: 1))
        }

        // MARK: - Acquisition state survives list refreshes (#51)

        private func tile(_ panel: SwitcherPanel, _ index: Int) throws -> SwitcherTileView {
            try #require(panel.tileForTesting(at: index))
        }

        private func renamed(_ id: String) -> SwitcherItem {
            SwitcherItem(
                id: id, window: nil, title: "Renamed \(id)",
                appName: "TestApp", icon: nil, tabCount: nil)
        }

        @Test func unavailableTileStaysUnavailableAfterAMetadataRefresh() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreviewUnavailable(id: "b")
            #expect(try tile(panel, 1).showsUnavailableStateForTesting)

            panel.update(items: [item("a"), renamed("b")], selectedIndex: 0)

            #expect(try tile(panel, 1).showsUnavailableStateForTesting)
            #expect(try !tile(panel, 1).skeletonIsAnimatingForTesting)
            #expect(try tile(panel, 0).showsLoadingStateForTesting)
        }

        @Test func permissionBlockedTilesStayBlockedAfterARefresh() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.setPreviewPermissionStatus(.denied)

            panel.update(items: [renamed("a"), item("b"), item("c")], selectedIndex: 0)

            for index in 0..<3 {
                #expect(try tile(panel, index).showsPermissionUnavailableStateForTesting)
                #expect(try !tile(panel, index).skeletonIsAnimatingForTesting)
            }
        }

        @Test func failedStateFollowsItsWindowAcrossAReorder() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreviewUnavailable(id: "b")

            panel.update(items: [item("b"), item("a")], selectedIndex: 0)

            #expect(try tile(panel, 0).showsUnavailableStateForTesting)
            #expect(try tile(panel, 1).showsLoadingStateForTesting)
        }

        @Test func slotReusedForAnotherWindowResetsToLoading() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.update(items: [item("a"), item("b")], selectedIndex: 0)
            panel.updatePreviewUnavailable(id: "b")

            // b closes and c takes its slot: nothing of b's failure may remain
            panel.update(items: [item("a"), item("c")], selectedIndex: 0)

            #expect(try tile(panel, 1).showsLoadingStateForTesting)
        }

        @Test func aNewSessionStartsWithoutThePreviousFailures() throws {
            let panel = SwitcherPanel(preferences: preferences, previews: previews, rasterizableBackground: true)
            panel.show(items: [item("a")], selectedIndex: 0, presentationMode: .persistent)
            panel.updatePreviewUnavailable(id: "a")
            panel.hide()

            panel.show(items: [item("a")], selectedIndex: 0, presentationMode: .persistent)
            panel.hide()

            #expect(try tile(panel, 0).showsLoadingStateForTesting)
        }
    }
}
