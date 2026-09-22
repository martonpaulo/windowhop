import AppKit
import XCTest
@testable import WindowHopCore

/// Mirrored panels must stay indistinguishable from each other. These drive the
/// group against one real screen repeated under different display ids, which
/// exercises the fan-out without needing multiple monitors attached to CI.
final class SwitcherPanelGroupTests: XCTestCase {
    private var group: SwitcherPanelGroup!
    /// Every selection announcement posted, as (window id, spoken text).
    private var announcements: [(id: AnyHashable, text: String)] = []

    override func setUp() {
        super.setUp()
        announcements = []
        group = SwitcherPanelGroup(announcer: SelectionAnnouncer { [unowned self] id, text in
            announcements.append((id, text))
        })
    }

    override func tearDown() {
        group.hide()
        group = nil
        super.tearDown()
    }

    private func targets(_ count: Int,
                         scale: CGFloat = 2) -> [(descriptor: DisplayDescriptor, screen: NSScreen)] {
        guard let screen = NSScreen.screens.first else { return [] }
        return (0..<count).map { index in
            (DisplayDescriptor(id: "display-\(index)",
                               name: "Display \(index)",
                               visibleFrame: screen.visibleFrame,
                               backingScale: scale),
             screen)
        }
    }

    private func items(_ count: Int) -> [SwitcherItem] {
        (0..<count).map {
            SwitcherItem(id: "item-\($0)" as AnyHashable,
                         window: nil,
                         title: "Window \($0)",
                         appName: "App",
                         icon: nil,
                         tabCount: nil)
        }
    }

    func testOnePanelIsCreatedPerTargetDisplay() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")

        group.prepare(for: targets(3), tileCount: 4, tileSize: NSSize(width: 200, height: 160))

        XCTAssertEqual(group.panelCountForTesting, 3)
    }

    func testShrinkingTheTargetSetLeavesNoOrphanPanel() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let tileSize = NSSize(width: 200, height: 160)

        group.prepare(for: targets(3), tileCount: 4, tileSize: tileSize)
        group.prepare(for: targets(1), tileCount: 4, tileSize: tileSize)

        XCTAssertEqual(group.panelCountForTesting, 1,
                       "unplugging a display must not leave a panel behind")
    }

    func testSelectionIsSynchronizedAcrossEveryPanel() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(5)
        group.prepare(for: targets(2), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))
        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

        group.select(3)

        for index in 0..<group.panelCountForTesting {
            let panel = try XCTUnwrap(group.panelForTesting(at: index))
            XCTAssertEqual(panel.selectedIndexForTesting, 3,
                           "panel \(index) drifted from the shared selection")
        }
        group.hide()
    }

    func testEndingASessionRemovesEveryPanelFromTheScreen() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(3)
        group.prepare(for: targets(2), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))
        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

        group.hide()

        for index in 0..<group.panelCountForTesting {
            let panel = try XCTUnwrap(group.panelForTesting(at: index))
            XCTAssertFalse(panel.isVisible, "panel \(index) stayed on screen after the session")
        }
    }

    func testEveryPanelReportsTheSameNavigationGrid() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(9)
        group.prepare(for: targets(3), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))
        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

        let columns = try XCTUnwrap(group.panelForTesting(at: 0)).columnsPerRow
        for index in 1..<group.panelCountForTesting {
            let panel = try XCTUnwrap(group.panelForTesting(at: index))
            XCTAssertEqual(panel.columnsPerRow, columns,
                           "arrow navigation would mean different things per display")
        }
        XCTAssertEqual(group.columnsPerRow, columns)
        group.hide()
    }

    func testCaptureScaleFollowsTheSharpestTargetDisplay() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        var mixed = targets(1, scale: 1)
        mixed.append(contentsOf: targets(1, scale: 3))

        group.prepare(for: mixed, tileCount: 2, tileSize: NSSize(width: 200, height: 160))

        XCTAssertEqual(group.captureScale, 3)
    }

    // MARK: - Selection announcement (#77)

    func testShowAcrossThreeDisplaysAnnouncesTheSelectionOnce() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(4)
        group.prepare(for: targets(3), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))

        group.show(items: list, selectedIndex: 1, presentationMode: .cycling)

        XCTAssertEqual(announcements.map(\.id), [list[1].id],
                       "one selection must speak once, not once per display")
    }

    func testNavigationAcrossMirroredPanelsAnnouncesTheNewTargetOnce() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(4)
        group.prepare(for: targets(3), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))
        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)
        announcements = []

        group.select(2)

        XCTAssertEqual(announcements.count, 1)
        XCTAssertEqual(announcements.first?.id, AnyHashable("item-2"))
        XCTAssertEqual(announcements.first?.text, "Window 2, App")
        for index in 0..<group.panelCountForTesting {
            let panel = try XCTUnwrap(group.panelForTesting(at: index))
            XCTAssertEqual(panel.selectedIndexForTesting, 2,
                           "panel \(index) must still show the selection visually")
        }
    }

    func testSingleDisplayShowAnnouncesOnce() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(3)
        group.prepare(for: targets(1), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))

        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

        XCTAssertEqual(announcements.map(\.id), [list[0].id])
    }

    func testANewSessionAfterHideAnnouncesAgain() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(3)
        group.prepare(for: targets(2), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))
        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)
        group.hide()
        announcements = []

        group.show(items: list, selectedIndex: 0, presentationMode: .cycling)

        XCTAssertEqual(announcements.map(\.id), [list[0].id])
    }

    func testTheSpokenTargetMatchesTheTileLabel() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let list = items(2)
        group.prepare(for: targets(1), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))

        group.show(items: list, selectedIndex: 1, presentationMode: .cycling)

        let tile = try XCTUnwrap(group.panelForTesting(at: 0)?.tileForTesting(at: 1))
        let label = try XCTUnwrap(tile.accessibilityLabel())
        XCTAssertEqual(announcements.last?.text, label)
    }
}
