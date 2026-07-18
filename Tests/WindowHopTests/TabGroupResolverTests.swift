import XCTest
@testable import WindowHopCore

final class TabGroupResolverTests: XCTestCase {
    private typealias Descriptor = TabGroupResolver.WindowDescriptor<String>
    private typealias State = TabGroupResolver.WindowTabState<String>

    private func window(_ id: String, _ title: String,
                        isTabbed: Bool = false, groupIds: [String]? = nil) -> Descriptor {
        Descriptor(id: id, title: title, isTabbed: isTabbed, groupIds: groupIds)
    }

    // MARK: - The canonical requirement

    /// Two browser windows with 5 tabs each must yield exactly 2 entries.
    /// Browsers expose one AX window per browser window: tab titles match no
    /// sibling window, so nothing is hidden and each window keeps its own count.
    func testTwoSafariWindowsWithFiveTabsEachProduceTwoEntries() {
        let windowA = window("A", "Apple — Safari")
        let windowB = window("B", "News — Safari")
        let changesA = TabGroupResolver.resolve(
            active: windowA,
            tabTitles: ["Apple — Safari", "Docs", "Mail", "Maps", "Music"],
            sameAppWindows: [windowB])
        XCTAssertEqual(changesA["A"], State(isTabbed: false, groupIds: ["A"]))
        XCTAssertNil(changesA["B"], "the other Safari window must not be marked as a tab")
        let changesB = TabGroupResolver.resolve(
            active: windowB,
            tabTitles: ["News — Safari", "Weather", "Stocks", "Notes", "Photos"],
            sameAppWindows: [windowA])
        XCTAssertEqual(changesB["B"], State(isTabbed: false, groupIds: ["B"]))
        XCTAssertNil(changesB["A"])
        // net effect: A and B both untabbed → exactly 2 entries, each with its own count
    }

    // MARK: - Native window tabs (Finder/Terminal style)

    /// With native NSWindow tabs every tab is a real AX window; only siblings whose
    /// titles match the active tab bar's titles are hidden.
    func testNativeTabSiblingsAreMarkedTabbed() {
        let active = window("A", "Documents")
        let sibling1 = window("B", "Downloads")
        let sibling2 = window("C", "Desktop")
        let unrelated = window("D", "Pictures")
        let changes = TabGroupResolver.resolve(
            active: active,
            tabTitles: ["Documents", "Downloads", "Desktop"],
            sameAppWindows: [sibling1, sibling2, unrelated])
        XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: ["A", "B", "C"]))
        XCTAssertEqual(changes["B"], State(isTabbed: true, groupIds: ["A", "B", "C"]))
        XCTAssertEqual(changes["C"], State(isTabbed: true, groupIds: ["A", "B", "C"]))
        XCTAssertNil(changes["D"], "windows outside the group are untouched")
    }

    func testDuplicateTabTitlesMatchDistinctSiblings() {
        let active = window("A", "untitled")
        let sibling1 = window("B", "untitled")
        let sibling2 = window("C", "untitled")
        let changes = TabGroupResolver.resolve(
            active: active,
            tabTitles: ["untitled", "untitled", "untitled"],
            sameAppWindows: [sibling1, sibling2])
        XCTAssertEqual(changes["B"]?.isTabbed, true)
        XCTAssertEqual(changes["C"]?.isTabbed, true)
        XCTAssertEqual(changes["A"]?.groupIds?.count, 3)
    }

    func testSwitchingActiveTabSwapsRoles() {
        // B was an inactive tab; the user selects it natively and it now reports the group
        let former = window("A", "Documents", isTabbed: false, groupIds: ["A", "B"])
        let nowActive = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(
            active: nowActive,
            tabTitles: ["Documents", "Downloads"],
            sameAppWindows: [former])
        XCTAssertEqual(changes["B"], State(isTabbed: false, groupIds: ["B", "A"]))
        XCTAssertEqual(changes["A"], State(isTabbed: true, groupIds: ["B", "A"]))
    }

    // MARK: - Group dissolution

    func testActiveWindowLeavingGroupIsCleared() {
        // a window that was a group's active tab now reports no tab bar (tab dragged out)
        let active = window("A", "Documents", isTabbed: false, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(active: active, tabTitles: nil,
                                               sameAppWindows: [])
        XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: nil))
    }

    func testInactiveTabReportingNilStaysTabbed() {
        // inactive tabs have no AXTabGroup child; a title-change event on one must
        // not clear its tabbed state
        let inactive = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(active: inactive, tabTitles: nil,
                                               sameAppWindows: [])
        XCTAssertTrue(changes.isEmpty)
    }

    func testStaleGroupMembersAreCleared() {
        let active = window("A", "Documents")
        let formerSibling = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        // A now reports a tab bar that no longer includes B's title
        let changes = TabGroupResolver.resolve(
            active: active,
            tabTitles: ["Documents", "Desktop"],
            sameAppWindows: [formerSibling])
        XCTAssertEqual(changes["B"], State(isTabbed: false, groupIds: nil))
    }

    // MARK: - Removal

    func testRemovalShrinksGroup() {
        let b = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B", "C"])
        let c = window("C", "Desktop", isTabbed: true, groupIds: ["A", "B", "C"])
        let changes = TabGroupResolver.resolveRemoval(removedId: "A",
                                                      groupIds: ["A", "B", "C"],
                                                      remainingWindows: [b, c])
        XCTAssertEqual(changes["B"], State(isTabbed: true, groupIds: ["B", "C"]))
        XCTAssertEqual(changes["C"], State(isTabbed: true, groupIds: ["B", "C"]))
    }

    func testRemovalDownToOneClearsTabState() {
        let b = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolveRemoval(removedId: "A",
                                                      groupIds: ["A", "B"],
                                                      remainingWindows: [b])
        XCTAssertEqual(changes["B"], State(isTabbed: false, groupIds: nil))
    }

    // MARK: - Display rule

    func testTabbedWindowsAreNeverDisplayed() {
        let state = WindowDisplayState(isMinimized: false, isAppHidden: false,
                                       isOwnWindow: false, isTabbed: true,
                                       isOnCurrentSpace: true, isOnActiveDisplay: true)
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, policy: .init()))
    }
}
