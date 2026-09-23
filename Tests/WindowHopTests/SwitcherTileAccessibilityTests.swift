import AppKit
import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// The tile advertises the AXButton role, so assistive technology expects the
/// standard Press action to activate the window exactly like a pointer click,
/// without ever reaching the separate Close custom action.
@MainActor
final class SwitcherTileAccessibilityTests: XCTestCase {
    private func makeItem(id: String, title: String) -> SwitcherItem {
        SwitcherItem(id: AnyHashable(id), window: nil, title: title,
                     appName: "Test App", icon: nil, tabCount: nil)
    }

    private func configuredTile(item: SwitcherItem,
                                mode: AppearanceMode = .appIcons) -> SwitcherTileView {
        let tile = SwitcherTileView()
        tile.configure(item: item, mode: mode, showTabCounts: false, preview: nil)
        return tile
    }

    func testPressWithoutCallbackReportsNoAction() {
        let tile = configuredTile(item: makeItem(id: "a", title: "A"))

        XCTAssertFalse(tile.accessibilityPerformPress())
    }

    func testPressDispatchesActivationExactlyOnce() {
        let tile = configuredTile(item: makeItem(id: "a", title: "A"))
        var activations = 0
        tile.onClick = { activations += 1 }

        XCTAssertTrue(tile.accessibilityPerformPress())
        XCTAssertEqual(activations, 1)
    }

    func testPressNeverInvokesCloseRequest() {
        let tile = configuredTile(item: makeItem(id: "a", title: "A"))
        var closeRequests = 0
        tile.onClick = {}
        tile.onCloseRequest = { closeRequests += 1 }

        XCTAssertTrue(tile.accessibilityPerformPress())
        XCTAssertEqual(closeRequests, 0)
    }

    /// Tiles are pooled, so a reused tile must activate its current target
    /// rather than the window it displayed before reconfiguration.
    func testPooledTileActivatesItsCurrentTarget() {
        let tile = configuredTile(item: makeItem(id: "a", title: "A"))
        var staleActivations = 0
        tile.onClick = { staleActivations += 1 }

        tile.configure(item: makeItem(id: "b", title: "B"),
                       mode: .windowPreviews, showTabCounts: true, preview: nil)
        var currentActivations = 0
        tile.onClick = { currentActivations += 1 }

        XCTAssertTrue(tile.accessibilityPerformPress())
        XCTAssertEqual(currentActivations, 1)
        XCTAssertEqual(staleActivations, 0)
    }

    /// Two same-app windows sharing a raw title are told apart by the collision
    /// qualifier in both the visible title and the spoken label (issue #92).
    func testCollidingTitlesGetDistinctLabels() {
        let work = SwitcherItem(id: AnyHashable("w"), window: nil, title: "Notes.txt",
                                displayTitle: "Notes.txt — Work",
                                appName: "TextEdit", icon: nil, tabCount: nil)
        let home = SwitcherItem(id: AnyHashable("h"), window: nil, title: "Notes.txt",
                                displayTitle: "Notes.txt — Home",
                                appName: "TextEdit", icon: nil, tabCount: nil)

        let workLabel = configuredTile(item: work).accessibilityLabel()
        let homeLabel = configuredTile(item: home).accessibilityLabel()

        XCTAssertEqual(workLabel, "Notes.txt — Work, TextEdit")
        XCTAssertNotEqual(workLabel, homeLabel)
        XCTAssertEqual(work.title, "Notes.txt", "the raw title stays for matching")
    }

    /// The expanded preview and the close confirmation name a colliding window
    /// the same way its tile does (issue #112).
    func testCollidingTitlesStayDistinctInPreviewAndCloseConfirmation() {
        let work = SwitcherItem(id: AnyHashable("w"), window: nil, title: "Notes.txt",
                                displayTitle: "Notes.txt — Work",
                                appName: "TextEdit", icon: nil, tabCount: nil)
        let home = SwitcherItem(id: AnyHashable("h"), window: nil, title: "Notes.txt",
                                displayTitle: "Notes.txt — Home",
                                appName: "TextEdit", icon: nil, tabCount: nil)

        XCTAssertEqual(SwitcherController.closeConfirmationMessage(for: work),
                       "Close “Notes.txt — Work” in TextEdit?")
        XCTAssertNotEqual(SwitcherController.closeConfirmationMessage(for: work),
                          SwitcherController.closeConfirmationMessage(for: home))

        let preview = ExpandedPreviewView()
        preview.updateMetadata(item: work)
        XCTAssertEqual(preview.accessibilityValue() as? String,
                       "Expanded preview of Notes.txt — Work, TextEdit")
    }

    func testDisplayTitleDefaultsToTheRawTitle() {
        let item = makeItem(id: "a", title: "Untitled")
        XCTAssertEqual(item.displayTitle, "Untitled")
        XCTAssertEqual(configuredTile(item: item).accessibilityLabel(), "Untitled, Test App")
    }

    /// A pooled tile parked out of the visible list has no callback, so it must
    /// not report a successful action in either appearance.
    func testDetachedTileRejectsPressInBothAppearances() {
        for mode in [AppearanceMode.appIcons, .windowPreviews] {
            let tile = configuredTile(item: makeItem(id: "a", title: "A"), mode: mode)
            tile.onClick = {}
            tile.onClick = nil

            XCTAssertFalse(tile.accessibilityPerformPress(), "mode: \(mode)")
        }
    }

    /// The tab count reaches the label through the String Catalog; an integer
    /// interpolated into `String(localized:)` would gain the locale's grouping
    /// ("1,200 tabs"), so the count keeps the digits it had before the catalog (#99).
    func testTabCountKeepsItsDigitsUnformatted() {
        let item = SwitcherItem(id: AnyHashable("a"), window: nil, title: "Docs",
                                appName: "Browser", icon: nil, tabCount: 1200)

        XCTAssertEqual(SwitcherTileView.accessibilityText(for: item, showTabCounts: true),
                       "Docs, Browser, 1200 tabs")
    }
}
