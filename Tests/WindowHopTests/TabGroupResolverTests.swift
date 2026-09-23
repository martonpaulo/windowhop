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
                        frame: CGRect?? = nil, reportedTabTitles: [String]? = nil) -> Descriptor {
        Descriptor(id: id, title: title, isTabbed: isTabbed, groupIds: groupIds,
                   frame: frame ?? groupFrame, reportedTabTitles: reportedTabTitles)
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

    // MARK: - Discovery order (an active tab can be discovered before its siblings)

    func testInactiveSiblingArrivingAfterItsActiveTabIsHidden() {
        let store = discover([activeArrival("A", tabs: ["A", "B"]), inactiveArrival("B")])
        XCTAssertEqual(visibleIds(store), ["A"])
        XCTAssertEqual(store["B"]?.groupIds.map(Set.init), ["A", "B"])
    }

    func testActiveTabArrivingAfterItsInactiveSiblingHidesIt() {
        let store = discover([inactiveArrival("B"), activeArrival("A", tabs: ["A", "B"])])
        XCTAssertEqual(visibleIds(store), ["A"])
        XCTAssertEqual(store["B"]?.groupIds.map(Set.init), ["A", "B"])
    }

    /// Resolving the arrival directly: only the waiting group changes.
    func testArrivalOfAnUnrelatedTitleChangesNothing() {
        let active = window("A", "A", groupIds: ["A"], reportedTabTitles: ["A", "B"])
        let changes = TabGroupResolver.resolveArrival(newWindow: window("X", "Unrelated"),
                                                      sameAppWindows: [active])
        XCTAssertTrue(changes.isEmpty)
    }

    /// A complete group (nothing unmatched) is not re-resolved when a window with
    /// one of its titles arrives: the newcomer stays visible and the group intact.
    func testArrivalDoesNotDisturbAnotherCompleteGroup() {
        let members = ["C", "D"]
        let completeActive = window("C", "C", groupIds: members, reportedTabTitles: ["C", "D"])
        let completeTab = window("D", "D", isTabbed: true, groupIds: members)
        let waitingActive = window("A", "A", groupIds: ["A"], frame: otherFrame,
                                   reportedTabTitles: ["A", "B"])
        let newcomer = window("B", "B", frame: otherFrame)
        let lookalike = window("E", "D")
        for others in [[completeActive, completeTab, waitingActive],
                       [waitingActive, completeTab, completeActive]] {
            let changes = TabGroupResolver.resolveArrival(newWindow: newcomer, sameAppWindows: others)
            XCTAssertEqual(changes["B"], State(isTabbed: true, groupIds: ["A", "B"]))
            XCTAssertNil(changes["C"])
            XCTAssertNil(changes["D"])
            let lookalikeChanges = TabGroupResolver.resolveArrival(newWindow: lookalike,
                                                                   sameAppWindows: others)
            XCTAssertTrue(lookalikeChanges.isEmpty, "C's group has no unmatched title")
        }
    }

    /// Startup enumeration returns windows in arbitrary order (Array(Set(...))).
    /// Every order of one active tab and two inactive siblings, plus an
    /// independent window, yields one entry for the group.
    func testStartupEnumerationInEitherOrderYieldsOneEntry() {
        let arrivals = [activeArrival("A", tabs: ["A", "B", "C"]), inactiveArrival("B"),
                        inactiveArrival("C"), inactiveArrival("X", frame: otherFrame)]
        for order in permutations(arrivals) {
            let store = discover(order)
            XCTAssertEqual(visibleIds(store), ["A", "X"], "order \(order.map(\.id))")
            XCTAssertEqual(store["A"]?.groupIds.map(Set.init), ["A", "B", "C"])
        }
    }

    private struct Arrival {
        let id: String
        let observation: TabObservation
        let frame: CGRect
    }

    private func activeArrival(_ id: String, tabs: [String]) -> Arrival {
        Arrival(id: id, observation: .group(tabs), frame: groupFrame)
    }

    private func inactiveArrival(_ id: String, frame: CGRect? = nil) -> Arrival {
        Arrival(id: id, observation: .standalone, frame: frame ?? groupFrame)
    }

    /// Discovers windows (titled by their id) one by one the way
    /// WindowStore.windowEvent does: the window's own resolution, then the arrival.
    private func discover(_ arrivals: [Arrival]) -> [String: Descriptor] {
        var store = [Descriptor]()
        func apply(_ changes: [String: State]) {
            store = store.map { $0.applying(changes[$0.id]) }
        }
        for arrival in arrivals {
            var reported: [String]?
            if case .group(let titles) = arrival.observation { reported = titles }
            store.append(window(arrival.id, arrival.id, frame: arrival.frame,
                                reportedTabTitles: reported))
            let newWindow = { store.first { $0.id == arrival.id }! }
            let others = { store.filter { $0.id != arrival.id } }
            if case .group = arrival.observation {
                apply(TabGroupResolver.resolve(active: newWindow(), observation: arrival.observation,
                                               sameAppWindows: others()))
            }
            apply(TabGroupResolver.resolveArrival(newWindow: newWindow(), sameAppWindows: others()))
        }
        return Dictionary(uniqueKeysWithValues: store.map { ($0.id, $0) })
    }

    private func visibleIds(_ store: [String: Descriptor]) -> Set<String> {
        Set(store.values.filter { isDisplayed($0, applying: [:]) }.map(\.id))
    }

    private func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { index -> [[T]] in
            var rest = items
            let head = rest.remove(at: index)
            return permutations(rest).map { [head] + $0 }
        }
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

    // MARK: - Live merge (#113)

    /// Measured on macOS 26: after Window ▸ Merge All Windows the three former
    /// windows are still tracked as standalone entries with their pre-merge frames,
    /// and no observed notification arrives. The session-start re-read then sees the
    /// active tab's bar and each inactive tab's empty children; in every read order
    /// the result is one entry that carries all three tabs.
    func testSessionRereadAfterALiveMergeYieldsOneEntryInAnyOrder() {
        let reads: [(id: String, observation: TabObservation)] = [
            ("A", .group(["A", "C", "B"])), ("B", .standalone), ("C", .standalone),
        ]
        for order in permutations(reads) {
            var store = [window("A", "A"),
                         window("B", "B", frame: otherFrame),
                         window("C", "C", frame: otherFrame.offsetBy(dx: -29, dy: -29))]
            for read in order {
                var reread = store.first { $0.id == read.id }!
                if case .group(let titles) = read.observation {
                    reread = window(reread.id, reread.title, isTabbed: reread.isTabbed,
                                    groupIds: reread.groupIds, frame: reread.frame,
                                    reportedTabTitles: titles)
                }
                // WindowStore.updateTabGroup's fast path: no bar and no group is a no-op
                if case .standalone = read.observation, reread.groupIds == nil { continue }
                let changes = TabGroupResolver.resolve(
                    active: reread, observation: read.observation,
                    sameAppWindows: store.filter { $0.id != read.id })
                store = store.map { $0.applying(changes[$0.id]) }
            }
            let visible = store.filter { isDisplayed($0, applying: [:]) }.map(\.id)
            XCTAssertEqual(visible, ["A"], "order \(order.map(\.id))")
            XCTAssertEqual(store.first?.groupIds.map(Set.init), ["A", "B", "C"])
        }
    }

    func testSessionRereadTargetsOnlyAppsWithTwoOrMoreEntries() {
        let entries: [(id: String, appId: String?)] = [
            ("te1", "TextEdit"), ("safari", "Safari"), ("te2", "TextEdit"),
            ("settings", nil), ("te3", "TextEdit"),
        ]
        XCTAssertEqual(TabGroupResolver.sessionRereadTargets(entries), ["te1", "te2", "te3"])
    }

    func testSessionRereadTargetsNothingWhenEveryAppHasOneEntry() {
        let entries: [(id: String, appId: String?)] = [
            ("te", "TextEdit"), ("safari", "Safari"), ("settings", nil), ("other", nil),
        ]
        XCTAssertTrue(TabGroupResolver.sessionRereadTargets(entries).isEmpty)
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
