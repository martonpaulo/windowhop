import AppKit
import XCTest
@testable import WindowHopCore

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
}
