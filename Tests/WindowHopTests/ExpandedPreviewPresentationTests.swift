import AppKit
import XCTest
@testable import WindowHopCore

/// The expanded preview must survive refreshes that change nothing about its
/// target, and must appear when its first image arrives after dwell settled.
final class ExpandedPreviewPresentationTests: XCTestCase {
    private var group: SwitcherPanelGroup!
    private var originalMode: AppearanceMode!

    override func setUp() {
        super.setUp()
        originalMode = Preferences.shared.appearanceMode
        Preferences.shared.appearanceMode = .windowPreviews
        group = SwitcherPanelGroup()
    }

    override func tearDown() {
        group.hide()
        group = nil
        Preferences.shared.appearanceMode = originalMode
        super.tearDown()
    }

    private func targets(_ count: Int) -> [(descriptor: DisplayDescriptor, screen: NSScreen)] {
        guard let screen = NSScreen.screens.first else { return [] }
        return (0..<count).map { index in
            (DisplayDescriptor(id: "display-\(index)", name: "Display \(index)",
                               visibleFrame: screen.visibleFrame, backingScale: 2), screen)
        }
    }

    private func items(_ count: Int, titleSuffix: String = "") -> [SwitcherItem] {
        (0..<count).map {
            SwitcherItem(id: "item-\($0)" as AnyHashable, window: nil,
                         title: "Window \($0)\(titleSuffix)", appName: "App",
                         icon: nil, tabCount: nil)
        }
    }

    private func image() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 48))
    }

    private func openedGroup(panelCount: Int = 1, items list: [SwitcherItem]) throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        group.prepare(for: targets(panelCount), tileCount: list.count,
                      tileSize: NSSize(width: 200, height: 160))
        group.update(items: list, selectedIndex: 0)
    }

    func testMetadataRefreshKeepsAnExpandedPreviewOnScreen() throws {
        let list = items(3)
        try openedGroup(items: list)
        group.showExpandedPreview(id: list[0].id, image: image())
        XCTAssertEqual(group.expandedPreviewID, list[0].id)

        // an unrelated title change arrives for the same, still selected window
        group.update(items: items(3, titleSuffix: " — edited"), selectedIndex: 0)

        XCTAssertEqual(group.expandedPreviewID, list[0].id)
    }

    func testSelectingAnotherWindowCollapsesTheExpandedPreview() throws {
        let list = items(3)
        try openedGroup(items: list)
        group.showExpandedPreview(id: list[0].id, image: image())

        group.update(items: list, selectedIndex: 1)

        XCTAssertNil(group.expandedPreviewID)
    }

    func testLosingTheExpandedWindowCollapsesThePreview() throws {
        let list = items(3)
        try openedGroup(items: list)
        group.showExpandedPreview(id: list[0].id, image: image())

        group.update(items: Array(list.dropFirst()), selectedIndex: 0)

        XCTAssertNil(group.expandedPreviewID)
    }

    func testAppIconsModeNeverKeepsAnExpandedPreview() throws {
        let list = items(3)
        try openedGroup(items: list)
        group.showExpandedPreview(id: list[0].id, image: image())

        Preferences.shared.appearanceMode = .appIcons
        group.update(items: list, selectedIndex: 0)

        XCTAssertNil(group.expandedPreviewID)
    }

    /// A late image for the currently expanded window repaints it in place
    /// rather than reopening the presentation.
    func testRepaintingKeepsTheSameExpandedWindow() throws {
        let list = items(3)
        try openedGroup(items: list)
        group.showExpandedPreview(id: list[0].id, image: image())

        group.showExpandedPreview(id: list[0].id, image: image())

        XCTAssertEqual(group.expandedPreviewID, list[0].id)
    }

    func testMirroredPanelsAgreeOnTheExpandedWindow() throws {
        let list = items(3)
        try openedGroup(panelCount: 3, items: list)
        group.showExpandedPreview(id: list[0].id, image: image())

        group.update(items: items(3, titleSuffix: " — edited"), selectedIndex: 0)

        XCTAssertEqual(group.expandedPreviewID, list[0].id)
        XCTAssertEqual(group.panelCountForTesting, 3)
    }
}
