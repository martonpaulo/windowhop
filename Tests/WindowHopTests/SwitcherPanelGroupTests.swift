import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// Mirrored panels must stay indistinguishable from each other. These drive the
    /// group against one real screen repeated under different display ids, which
    /// exercises the fan-out without needing multiple monitors attached to CI.
    @MainActor
    @Suite(.needsDisplay)
    final class SwitcherPanelGroupTests {
        private var group: SwitcherPanelGroup!
        private var isolated: IsolatedPreferences!
        /// Every selection announcement posted, as (window id, spoken text).
        private var announcements: [(id: AnyHashable, text: String)] = []

        init() throws {
            announcements = []
            isolated = try IsolatedPreferences()
            let preferences = isolated.preferences
            group = SwitcherPanelGroup(
                preferences: preferences, previews: isolated.previews,
                announcer: SelectionAnnouncer(preferences: preferences) { [unowned self] id, text in
                    announcements.append((id, text))
                })
        }

        isolated deinit {
            group.hide()
            group = nil
            isolated.remove()
            isolated = nil
        }

        private func targets(
            _ count: Int,
            scale: CGFloat = 2
        ) -> [(descriptor: DisplayDescriptor, screen: NSScreen)] {
            guard let screen = NSScreen.screens.first else { return [] }
            return (0..<count).map { index in
                (
                    DisplayDescriptor(
                        id: "display-\(index)",
                        name: "Display \(index)",
                        visibleFrame: screen.visibleFrame,
                        backingScale: scale),
                    screen
                )
            }
        }

        private func items(_ count: Int) -> [SwitcherItem] {
            (0..<count).map {
                SwitcherItem(
                    id: "item-\($0)" as AnyHashable,
                    window: nil,
                    title: "Window \($0)",
                    appName: "App",
                    icon: nil,
                    tabCount: nil)
            }
        }

        @Test func onePanelIsCreatedPerTargetDisplay() throws {

            group.prepare(for: targets(3), tileCount: 4, tileSize: NSSize(width: 200, height: 160))

            #expect(group.panelCountForTesting == 3)
        }

        @Test func shrinkingTheTargetSetLeavesNoOrphanPanel() throws {
            let tileSize = NSSize(width: 200, height: 160)

            group.prepare(for: targets(3), tileCount: 4, tileSize: tileSize)
            group.prepare(for: targets(1), tileCount: 4, tileSize: tileSize)

            #expect(
                group.panelCountForTesting == 1,
                "unplugging a display must not leave a panel behind")
        }

        @Test func selectionIsSynchronizedAcrossEveryPanel() throws {
            let list = items(5)
            group.prepare(
                for: targets(2), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

            group.select(3)

            for index in 0..<group.panelCountForTesting {
                let panel = try #require(group.panelForTesting(at: index))
                #expect(
                    panel.selectedIndexForTesting == 3,
                    "panel \(index) drifted from the shared selection")
            }
            group.hide()
        }

        @Test func endingASessionRemovesEveryPanelFromTheScreen() throws {
            let list = items(3)
            group.prepare(
                for: targets(2), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

            group.hide()

            for index in 0..<group.panelCountForTesting {
                let panel = try #require(group.panelForTesting(at: index))
                #expect(!panel.isVisible, "panel \(index) stayed on screen after the session")
            }
        }

        @Test func everyPanelReportsTheSameNavigationGrid() throws {
            let list = items(9)
            group.prepare(
                for: targets(3), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

            let columns = try #require(group.panelForTesting(at: 0)).columnsPerRow
            for index in 1..<group.panelCountForTesting {
                let panel = try #require(group.panelForTesting(at: index))
                #expect(
                    panel.columnsPerRow == columns,
                    "arrow navigation would mean different things per display")
            }
            #expect(group.columnsPerRow == columns)
            group.hide()
        }

        @Test func captureScaleFollowsTheSharpestTargetDisplay() throws {
            var mixed = targets(1, scale: 1)
            mixed.append(contentsOf: targets(1, scale: 3))

            group.prepare(for: mixed, tileCount: 2, tileSize: NSSize(width: 200, height: 160))

            #expect(group.captureScale == 3)
        }

        // MARK: - Selection announcement (#77)

        @Test func showAcrossThreeDisplaysAnnouncesTheSelectionOnce() throws {
            let list = items(4)
            group.prepare(
                for: targets(3), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))

            group.show(items: list, selectedIndex: 1, presentationMode: .cycling)

            #expect(
                announcements.map(\.id) == [list[1].id],
                "one selection must speak once, not once per display")
        }

        @Test func navigationAcrossMirroredPanelsAnnouncesTheNewTargetOnce() throws {
            let list = items(4)
            group.prepare(
                for: targets(3), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)
            announcements = []

            group.select(2)

            #expect(announcements.count == 1)
            #expect(announcements.first?.id == AnyHashable("item-2"))
            #expect(announcements.first?.text == "Window 2, App")
            for index in 0..<group.panelCountForTesting {
                let panel = try #require(group.panelForTesting(at: index))
                #expect(
                    panel.selectedIndexForTesting == 2,
                    "panel \(index) must still show the selection visually")
            }
        }

        @Test func singleDisplayShowAnnouncesOnce() throws {
            let list = items(3)
            group.prepare(
                for: targets(1), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))

            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

            #expect(announcements.map(\.id) == [list[0].id])
        }

        @Test func aNewSessionAfterHideAnnouncesAgain() throws {
            let list = items(3)
            group.prepare(
                for: targets(2), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)
            group.hide()
            announcements = []

            group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

            #expect(announcements.map(\.id) == [list[0].id])
        }

        @Test func theSpokenTargetMatchesTheTileLabel() throws {
            let list = items(2)
            group.prepare(
                for: targets(1), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))

            group.show(items: list, selectedIndex: 1, presentationMode: .cycling)

            let tile = try #require(group.panelForTesting(at: 0)?.tileForTesting(at: 1))
            let label = try #require(tile.accessibilityLabel())
            #expect(announcements.last?.text == label)
        }

        // MARK: - Reconciliation announcement (#75)

        @Test func removingTheSelectedWindowAnnouncesTheTargetConfirmationWillActivate() throws {
            let list = items(3)
            group.prepare(
                for: targets(1), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 1, presentationMode: .cycling)
            announcements = []

            let survivors = [list[0], list[2]]
            group.update(items: survivors, selectedIndex: 1)

            #expect(
                announcements.count == 1,
                "the spoken target went stale when the selected window disappeared")
            #expect(
                announcements.first?.id == survivors[1].id,
                "the announced window must be the one confirmation activates")
            #expect(announcements.first?.text == "Window 2, App")
        }

        @Test func aMetadataRefreshKeepingTheSelectionAnnouncesNothing() throws {
            let list = items(3)
            group.prepare(
                for: targets(1), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 1, presentationMode: .cycling)
            announcements = []

            var renamed = list
            renamed[1] = SwitcherItem(
                id: list[1].id, window: nil, title: "Renamed",
                appName: "App", icon: nil, tabCount: nil)
            group.update(items: renamed, selectedIndex: 1)

            #expect(announcements.isEmpty, "a title change is not a selection change")
        }

        @Test func anAppendedWindowAnnouncesNothing() throws {
            let list = items(3)
            group.prepare(
                for: targets(1), tileCount: 4,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: Array(list.prefix(2)), selectedIndex: 1, presentationMode: .cycling)
            announcements = []

            group.update(items: list, selectedIndex: 1)

            #expect(announcements.isEmpty)
        }

        @Test func reconciliationAcrossMirroredPanelsAnnouncesOncePerChange() throws {
            let list = items(4)
            group.prepare(
                for: targets(2), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.show(items: list, selectedIndex: 2, presentationMode: .cycling)
            announcements = []

            group.update(items: [list[0], list[1], list[3]], selectedIndex: 2)
            group.update(items: [list[0], list[1]], selectedIndex: 1)

            #expect(announcements.map(\.id) == [list[3].id, list[1].id])
        }

        @Test func theAnnouncedTargetIsTheOneConfirmationActivates() throws {
            let list = items(3)
            group.prepare(
                for: targets(1), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            var state = SwitcherState()
            _ = state.trigger(backward: false, itemCount: list.count)
            group.show(items: list, selectedIndex: state.selectedIndex, presentationMode: .cycling)
            announcements = []

            // the selected window vanishes: the controller keeps the old index,
            // which the state machine clamps (SwitcherController.refreshDuringSession)
            let survivors = list.filter { $0.id != list[state.selectedIndex].id }
            _ = state.listChanged(itemCount: survivors.count, preferredIndex: nil)
            group.update(items: survivors, selectedIndex: state.selectedIndex)

            guard case .activate(let confirmed) = state.returnKey() else {
                Issue.record("Return must activate the selection")
                return
            }
            #expect(announcements.map(\.id) == [survivors[confirmed].id])
        }
    }
}
