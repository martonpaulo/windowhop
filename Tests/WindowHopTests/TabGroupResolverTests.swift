import XCTest
@testable import WindowHopCore

final class TabGroupResolverTests: XCTestCase {
    private typealias Descriptor = TabGroupResolver.WindowDescriptor<String>
    private typealias State = TabGroupResolver.WindowTabState<String>

    /// Native tabs of one window share that window's frame.
    private let groupFrame = CGRect(x: 100, y: 80, width: 900, height: 600)
    private let otherFrame = CGRect(x: 400, y: 300, width: 700, height: 500)

    private func window(_ id: String, _ title: String,
                        isTabbed: Bool = false, groupIds: [String]? = nil,
                        frame: CGRect?? = nil) -> Descriptor {
        Descriptor(id: id, title: title, isTabbed: isTabbed, groupIds: groupIds,
                   frame: frame ?? groupFrame)
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
            observation: .group(["Apple — Safari", "Docs", "Mail", "Maps", "Music"]),
            sameAppWindows: [windowB])
        XCTAssertEqual(changesA["A"], State(isTabbed: false, groupIds: ["A"]))
        XCTAssertNil(changesA["B"], "the other Safari window must not be marked as a tab")
        let changesB = TabGroupResolver.resolve(
            active: windowB,
            observation: .group(["News — Safari", "Weather", "Stocks", "Notes", "Photos"]),
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
            observation: .group(["Documents", "Downloads", "Desktop"]),
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
            observation: .group(["untitled", "untitled", "untitled"]),
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
            observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [former])
        XCTAssertEqual(changes["B"], State(isTabbed: false, groupIds: ["B", "A"]))
        XCTAssertEqual(changes["A"], State(isTabbed: true, groupIds: ["B", "A"]))
    }

    // MARK: - Group dissolution

    func testActiveWindowLeavingGroupIsCleared() {
        // a window that was a group's active tab now reports no tab bar (tab dragged out)
        let active = window("A", "Documents", isTabbed: false, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(active: active, observation: .standalone,
                                               sameAppWindows: [])
        XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: nil))
    }

    func testInactiveTabReportingNilStaysTabbed() {
        // inactive tabs have no AXTabGroup child; a title-change event on one must
        // not clear its tabbed state
        let inactive = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(active: inactive, observation: .standalone,
                                               sameAppWindows: [])
        XCTAssertTrue(changes.isEmpty)
    }

    func testStaleGroupMembersAreCleared() {
        let active = window("A", "Documents")
        let formerSibling = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        // A now reports a tab bar that no longer includes B's title
        let changes = TabGroupResolver.resolve(
            active: active,
            observation: .group(["Documents", "Desktop"]),
            sameAppWindows: [formerSibling])
        XCTAssertEqual(changes["B"], State(isTabbed: false, groupIds: nil))
    }

    // MARK: - Independent groups in one app

    /// Two established native tab groups in one app: refreshing one must not
    /// dissolve the other, or its inactive tab reappears as its own entry.
    func testRefreshingOneGroupPreservesAnotherGroupInTheSameApp() {
        let groupOne = ["A", "B"]
        let groupTwo = ["C", "D"]
        let activeOne = window("A", "A", groupIds: groupOne)
        let inactiveOne = window("B", "B", isTabbed: true, groupIds: groupOne)
        let activeTwo = window("C", "C", groupIds: groupTwo, frame: otherFrame)
        let inactiveTwo = window("D", "D", isTabbed: true, groupIds: groupTwo, frame: otherFrame)

        let changes = TabGroupResolver.resolve(
            active: activeOne,
            observation: .group(["A", "B"]),
            sameAppWindows: [inactiveOne, activeTwo, inactiveTwo])

        XCTAssertEqual(changes["B"], State(isTabbed: true, groupIds: groupOne))
        XCTAssertNil(changes["C"], "the other group's active tab must be untouched")
        XCTAssertNil(changes["D"], "the other group's inactive tab must stay hidden")
        XCTAssertFalse(isDisplayed(inactiveTwo, applying: changes),
                       "D must remain excluded as an inactive tab")
    }

    /// The symmetric refresh must hold too, so neither group wins by ordering.
    func testRefreshingTheOtherGroupPreservesTheFirst() {
        let groupOne = ["A", "B"]
        let groupTwo = ["C", "D"]
        let inactiveOne = window("B", "B", isTabbed: true, groupIds: groupOne, frame: otherFrame)
        let activeTwo = window("C", "C", groupIds: groupTwo)
        let inactiveTwo = window("D", "D", isTabbed: true, groupIds: groupTwo)

        let changes = TabGroupResolver.resolve(
            active: activeTwo,
            observation: .group(["C", "D"]),
            sameAppWindows: [window("A", "A", groupIds: groupOne, frame: otherFrame),
                             inactiveOne, inactiveTwo])

        XCTAssertEqual(changes["D"], State(isTabbed: true, groupIds: groupTwo))
        XCTAssertNil(changes["A"])
        XCTAssertNil(changes["B"])
        XCTAssertFalse(isDisplayed(inactiveOne, applying: changes))
    }

    /// A window that truly leaves the refreshed group still gets cleared, while
    /// an unrelated group in the same app survives the same update.
    func testFormerMemberIsClearedWithoutDisturbingAnotherGroup() {
        let groupOne = ["A", "B"]
        let groupTwo = ["C", "D"]
        let formerSibling = window("B", "B", isTabbed: true, groupIds: groupOne)
        let inactiveTwo = window("D", "D", isTabbed: true, groupIds: groupTwo, frame: otherFrame)

        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: groupOne),
            observation: .group(["A"]),
            sameAppWindows: [formerSibling, window("C", "C", groupIds: groupTwo, frame: otherFrame),
                             inactiveTwo])

        XCTAssertEqual(changes["B"], State(isTabbed: false, groupIds: nil))
        XCTAssertTrue(isDisplayed(formerSibling, applying: changes),
                      "B left the group and must become its own entry")
        XCTAssertNil(changes["D"])
        XCTAssertFalse(isDisplayed(inactiveTwo, applying: changes))
    }

    // MARK: - Title collisions (an independent window shares an inactive tab's title)

    /// Active A (Documents) with inactive tab B (Downloads), plus an independent
    /// window C also titled Downloads at another position. Listing C before B once
    /// hid C and left the real tab B visible.
    func testIndependentSameTitleWindowStaysVisibleWhenListedBeforeTheInactiveTab() {
        let (active, tab, independent) = collisionFixture()
        let changes = TabGroupResolver.resolve(active: active, observation: .group(["Documents", "Downloads"]),
                                               sameAppWindows: [independent, tab])
        XCTAssertTrue(isDisplayed(independent, applying: changes))
        XCTAssertFalse(isDisplayed(tab, applying: changes))
        XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: ["A", "B"]))
    }

    func testIndependentSameTitleWindowStaysVisibleWhenListedAfterTheInactiveTab() {
        let (active, tab, independent) = collisionFixture()
        let changes = TabGroupResolver.resolve(active: active, observation: .group(["Documents", "Downloads"]),
                                               sameAppWindows: [tab, independent])
        XCTAssertTrue(isDisplayed(independent, applying: changes))
        XCTAssertFalse(isDisplayed(tab, applying: changes))
        XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: ["A", "B"]))
    }

    private func collisionFixture() -> (Descriptor, Descriptor, Descriptor) {
        (window("A", "Documents"), window("B", "Downloads"),
         window("C", "Downloads", frame: otherFrame))
    }

    func testDuplicateTitleTabsSharingTheGroupFrameAreAllMatched() {
        let tabs = [window("B", "untitled"), window("C", "untitled")]
        let independent = window("D", "untitled", frame: otherFrame)
        for order in [tabs + [independent], [independent] + tabs.reversed()] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "untitled"),
                observation: .group(["untitled", "untitled", "untitled"]),
                sameAppWindows: order)
            XCTAssertFalse(isDisplayed(tabs[0], applying: changes))
            XCTAssertFalse(isDisplayed(tabs[1], applying: changes))
            XCTAssertTrue(isDisplayed(independent, applying: changes))
            XCTAssertEqual(Set(changes["A"]?.groupIds ?? []), ["A", "B", "C"])
        }
    }

    /// Two unrecorded windows share the tab's title and the group's frame (say two
    /// maximized windows), but the tab bar holds that title once: nothing tells
    /// them apart, so neither is hidden.
    func testSameTitleSameFrameTieLeavesCandidatesVisible() {
        let first = window("B", "Downloads")
        let second = window("C", "Downloads")
        for order in [[first, second], [second, first]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
                sameAppWindows: order)
            XCTAssertTrue(isDisplayed(first, applying: changes))
            XCTAssertTrue(isDisplayed(second, applying: changes))
            XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: ["A"]))
        }
    }

    /// Recorded membership separates a tie: the window already in this group wins.
    func testRecordedMemberWinsASameFrameTie() {
        let member = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let stranger = window("C", "Downloads")
        for order in [[member, stranger], [stranger, member]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents", groupIds: ["A", "B"]),
                observation: .group(["Documents", "Downloads"]), sameAppWindows: order)
            XCTAssertFalse(isDisplayed(member, applying: changes))
            XCTAssertTrue(isDisplayed(stranger, applying: changes))
        }
    }

    /// The active tab of another group shows its own tab bar; it is never taken
    /// as an inactive tab here, even with a matching title and frame.
    func testAnotherGroupsActiveTabIsNeverMatched() {
        let otherActive = window("C", "Downloads", groupIds: ["C", "D"])
        let otherTab = window("D", "Music", isTabbed: true, groupIds: ["C", "D"])
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [otherActive, otherTab])
        XCTAssertNil(changes["C"])
        XCTAssertTrue(isDisplayed(otherActive, applying: changes))
        XCTAssertFalse(isDisplayed(otherTab, applying: changes))
    }

    func testUnknownFrameRanksBelowAFrameEqualCandidate() {
        let tab = window("B", "Downloads")
        let unknown = window("C", "Downloads", frame: .some(nil))
        for order in [[unknown, tab], [tab, unknown]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
                sameAppWindows: order)
            XCTAssertFalse(isDisplayed(tab, applying: changes))
            XCTAssertTrue(isDisplayed(unknown, applying: changes))
        }
    }

    /// Without any frame-equal candidate, a single unknown-frame title match is
    /// still the tab: geometry that cannot be read must not break grouping.
    func testASingleUnknownFrameCandidateIsStillMatched() {
        let unknown = window("B", "Downloads", frame: .some(nil))
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [unknown])
        XCTAssertFalse(isDisplayed(unknown, applying: changes))
    }

    /// Measured on macOS 26: after Window ▸ Merge All Windows an inactive tab keeps
    /// reporting its pre-merge frame. A different frame ranks last but does not
    /// exclude the only candidate, or every freshly merged tab would leak out.
    func testMergedTabWithStalePreMergeFrameIsStillMatched() {
        let stale = window("B", "Downloads", frame: otherFrame)
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [stale])
        XCTAssertFalse(isDisplayed(stale, applying: changes))
    }

    /// Two same-title candidates whose frames both differ from the group's (a stale
    /// merged tab and an independent window) cannot be told apart: both stay visible.
    func testTwoDifferentFrameCandidatesForOneTitleStayVisible() {
        let stale = window("B", "Downloads", frame: otherFrame)
        let independent = window("C", "Downloads", frame: otherFrame.offsetBy(dx: 40, dy: 40))
        for order in [[stale, independent], [independent, stale]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
                sameAppWindows: order)
            XCTAssertTrue(isDisplayed(stale, applying: changes))
            XCTAssertTrue(isDisplayed(independent, applying: changes))
        }
    }

    /// Frames are compared in whole points; sub-point AX noise is not a new window.
    func testSubPointFrameDifferenceStillMatches() {
        let nudged = window("B", "Downloads", frame: groupFrame.offsetBy(dx: 0.3, dy: -0.2))
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [nudged])
        XCTAssertFalse(isDisplayed(nudged, applying: changes))
    }

    // MARK: - Incomplete observations (a failed AX read is not evidence)

    func testFailedTabTitleReadIsUnknown() {
        let observation = classify(tabGroup: [tab("A"), tab("B"), tab(title: .failed)])
        XCTAssertEqual(observation, .unknown)
    }

    func testFailedTabSubroleReadIsUnknown() {
        let failedSubrole = TabObservation.TabButtonFacts(subrole: .failed, title: .value("C"))
        XCTAssertEqual(classify(tabGroup: [tab("A"), tab("B"), failedSubrole]), .unknown)
    }

    func testFailedChildrenReadIsUnknown() {
        XCTAssertEqual(TabObservation.classify(children: .failed), .unknown)
        let failedTabBar = TabObservation.ChildFacts(role: .value("AXTabGroup"), tabs: .failed)
        XCTAssertEqual(TabObservation.classify(children: .value([failedTabBar])), .unknown)
        let unreadableChild = TabObservation.ChildFacts(role: .failed, tabs: .failed)
        XCTAssertEqual(TabObservation.classify(children: .value([unreadableChild])), .unknown,
                       "an unreadable child could have been the tab bar")
    }

    func testNoTabGroupIsStandalone() {
        let button = TabObservation.ChildFacts(role: .value("AXButton"), tabs: .absent)
        let roleless = TabObservation.ChildFacts(role: .absent, tabs: .absent)
        XCTAssertEqual(TabObservation.classify(children: .value([button, roleless])), .standalone)
        XCTAssertEqual(TabObservation.classify(children: .value([])), .standalone)
        XCTAssertEqual(TabObservation.classify(children: .absent), .standalone)
        XCTAssertEqual(classify(tabGroup: [tab("A")]), .standalone,
                       "a tab bar with one tab is no group")
    }

    func testEmptyTitleWithNoValueIsAGroupMember() {
        XCTAssertEqual(classify(tabGroup: [tab("A"), tab(title: .absent)]), .group(["A", ""]))
    }

    func testNonTabButtonChildrenOfTheTabBarAreIgnored() {
        let addButton = TabObservation.TabButtonFacts(subrole: .value("AXButton"), title: .value("+"))
        let noSubrole = TabObservation.TabButtonFacts(subrole: .absent, title: .failed)
        XCTAssertEqual(classify(tabGroup: [tab("A"), addButton, noSubrole, tab("B")]),
                       .group(["A", "B"]))
    }

    /// A complete tab bar decides even when an unrelated child could not be read.
    func testCompleteTabBarDecidesDespiteAnUnreadableSibling() {
        let unreadable = TabObservation.ChildFacts(role: .failed, tabs: .failed)
        let tabBar = TabObservation.ChildFacts(role: .value("AXTabGroup"),
                                               tabs: .value([tab("A"), tab("B")]))
        XCTAssertEqual(TabObservation.classify(children: .value([unreadable, tabBar])),
                       .group(["A", "B"]))
    }

    /// A/B/C group; C's read fails while A and B succeed. The partial list used to
    /// be treated as complete and C was released as its own entry.
    func testUnknownObservationKeepsAThreeMemberGroup() {
        let members = ["A", "B", "C"]
        let tabB = window("B", "B", isTabbed: true, groupIds: members)
        let tabC = window("C", "C", isTabbed: true, groupIds: members)
        let observation = classify(tabGroup: [tab("A"), tab("B"), tab(title: .failed)])
        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: members), observation: observation,
            sameAppWindows: [tabB, tabC])
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(isDisplayed(tabB, applying: changes))
        XCTAssertFalse(isDisplayed(tabC, applying: changes))
    }

    func testUnknownObservationLeavesUnrelatedGroupsUntouched() {
        let otherTab = window("D", "D", isTabbed: true, groupIds: ["C", "D"], frame: otherFrame)
        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: ["A", "B"]), observation: .unknown,
            sameAppWindows: [window("B", "B", isTabbed: true, groupIds: ["A", "B"]),
                             window("C", "C", groupIds: ["C", "D"], frame: otherFrame), otherTab])
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(isDisplayed(otherTab, applying: changes))
    }

    /// The first complete read after a failed one restores the group: no restart,
    /// no retry timer.
    func testCompleteObservationAfterUnknownRecoversTheGroup() {
        let active = window("A", "A")
        let tabB = window("B", "B")
        let tabC = window("C", "C")
        let failed = TabGroupResolver.resolve(active: active, observation: .unknown,
                                              sameAppWindows: [tabB, tabC])
        XCTAssertTrue(failed.isEmpty)
        let recovered = TabGroupResolver.resolve(active: active, observation: .group(["A", "B", "C"]),
                                                 sameAppWindows: [tabB, tabC])
        XCTAssertFalse(isDisplayed(tabB, applying: recovered))
        XCTAssertFalse(isDisplayed(tabC, applying: recovered))
        XCTAssertEqual(recovered["A"], State(isTabbed: false, groupIds: ["A", "B", "C"]))
    }

    /// A complete read that no longer lists C still releases C: only incomplete
    /// reads are ignored.
    func testCompleteObservationStillRemovesADepartedMember() {
        let members = ["A", "B", "C"]
        let tabC = window("C", "C", isTabbed: true, groupIds: members)
        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: members), observation: .group(["A", "B"]),
            sameAppWindows: [window("B", "B", isTabbed: true, groupIds: members), tabC])
        XCTAssertEqual(changes["C"], State(isTabbed: false, groupIds: nil))
        XCTAssertTrue(isDisplayed(tabC, applying: changes))
        XCTAssertEqual(changes["A"], State(isTabbed: false, groupIds: ["A", "B"]))
    }

    private func tab(_ title: String) -> TabObservation.TabButtonFacts {
        tab(title: .value(title))
    }

    private func tab(title: AttributeRead<String>) -> TabObservation.TabButtonFacts {
        TabObservation.TabButtonFacts(subrole: .value("AXTabButton"), title: title)
    }

    /// A window whose only child is a tab bar holding `tabs`.
    private func classify(tabGroup tabs: [TabObservation.TabButtonFacts]) -> TabObservation {
        TabObservation.classify(children: .value([
            TabObservation.ChildFacts(role: .value("AXTabGroup"), tabs: .value(tabs)),
        ]))
    }

    /// Applies the resolver's sparse change map the way WindowStore does, then
    /// asks the real eligibility rule whether the window becomes an entry.
    private func isDisplayed(_ descriptor: Descriptor,
                             applying changes: [String: State]) -> Bool {
        let isTabbed = changes[descriptor.id]?.isTabbed ?? descriptor.isTabbed
        return WindowEligibility.shouldDisplay(
            WindowDisplayState(isMinimized: false, isAppHidden: false, isOwnWindow: false,
                               isTabbed: isTabbed,
                               isOnCurrentSpace: true, isOnActiveDisplay: true),
            policy: .init())
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
