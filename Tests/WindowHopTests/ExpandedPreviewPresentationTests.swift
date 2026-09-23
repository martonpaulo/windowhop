import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// The expanded preview must survive refreshes that change nothing about its
    /// target, and must appear when its first image arrives after dwell settled.
    @MainActor
    @Suite(.needsDisplay)
    final class ExpandedPreviewPresentationTests {
        private var group: SwitcherPanelGroup!
        private var isolated: IsolatedPreferences!
        private var preferences: Preferences { isolated.preferences }

        init() throws {
            isolated = try IsolatedPreferences()
            preferences.appearanceMode = .windowPreviews
            group = SwitcherPanelGroup(preferences: preferences, previews: isolated.previews)
        }

        isolated deinit {
            group.hide()
            group = nil
            isolated.remove()
            isolated = nil
        }

        private func targets(_ count: Int) -> [(descriptor: DisplayDescriptor, screen: NSScreen)] {
            guard let screen = NSScreen.screens.first else { return [] }
            return (0..<count).map { index in
                (
                    DisplayDescriptor(
                        id: "display-\(index)", name: "Display \(index)",
                        visibleFrame: screen.visibleFrame, backingScale: 2), screen
                )
            }
        }

        private func items(_ count: Int, titleSuffix: String = "") -> [SwitcherItem] {
            (0..<count).map {
                SwitcherItem(
                    id: "item-\($0)" as AnyHashable, window: nil,
                    title: "Window \($0)\(titleSuffix)", appName: "App",
                    icon: nil, tabCount: nil)
            }
        }

        private func image() -> NSImage {
            NSImage(size: NSSize(width: 64, height: 48))
        }

        private func openedGroup(panelCount: Int = 1, items list: [SwitcherItem]) throws {
            group.prepare(
                for: targets(panelCount), tileCount: list.count,
                tileSize: NSSize(width: 200, height: 160))
            group.update(items: list, selectedIndex: 0)
        }

        @Test func metadataRefreshKeepsAnExpandedPreviewOnScreen() throws {
            let list = items(3)
            try openedGroup(items: list)
            group.showExpandedPreview(id: list[0].id, image: image())
            #expect(group.expandedPreviewID == list[0].id)

            // an unrelated title change arrives for the same, still selected window
            group.update(items: items(3, titleSuffix: " — edited"), selectedIndex: 0)

            #expect(group.expandedPreviewID == list[0].id)
        }

        @Test func selectingAnotherWindowCollapsesTheExpandedPreview() throws {
            let list = items(3)
            try openedGroup(items: list)
            group.showExpandedPreview(id: list[0].id, image: image())

            group.update(items: list, selectedIndex: 1)

            #expect(group.expandedPreviewID == nil)
        }

        @Test func losingTheExpandedWindowCollapsesThePreview() throws {
            let list = items(3)
            try openedGroup(items: list)
            group.showExpandedPreview(id: list[0].id, image: image())

            group.update(items: Array(list.dropFirst()), selectedIndex: 0)

            #expect(group.expandedPreviewID == nil)
        }

        @Test func appIconsModeNeverKeepsAnExpandedPreview() throws {
            let list = items(3)
            try openedGroup(items: list)
            group.showExpandedPreview(id: list[0].id, image: image())

            preferences.appearanceMode = .appIcons
            group.update(items: list, selectedIndex: 0)

            #expect(group.expandedPreviewID == nil)
        }

        /// A late image for the currently expanded window repaints it in place
        /// rather than reopening the presentation.
        @Test func repaintingKeepsTheSameExpandedWindow() throws {
            let list = items(3)
            try openedGroup(items: list)
            group.showExpandedPreview(id: list[0].id, image: image())

            group.showExpandedPreview(id: list[0].id, image: image())

            #expect(group.expandedPreviewID == list[0].id)
        }

        @Test func mirroredPanelsAgreeOnTheExpandedWindow() throws {
            let list = items(3)
            try openedGroup(panelCount: 3, items: list)
            group.showExpandedPreview(id: list[0].id, image: image())

            group.update(items: items(3, titleSuffix: " — edited"), selectedIndex: 0)

            #expect(group.expandedPreviewID == list[0].id)
            #expect(group.panelCountForTesting == 3)
        }
    }
}
