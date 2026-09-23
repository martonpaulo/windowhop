import Foundation
import Testing

@testable import WindowHopKit

struct TabGroupResolverTests {
    private typealias Descriptor = TabGroupResolver.WindowDescriptor<String>
    private typealias State = TabGroupResolver.WindowTabState<String>

    /// Native tabs of one window share that window's frame.
    private let groupFrame = CGRect(x: 100, y: 80, width: 900, height: 600)
    private let otherFrame = CGRect(x: 400, y: 300, width: 700, height: 500)

    private func window(
        _ id: String, _ title: String,
        isTabbed: Bool = false, groupIds: [String]? = nil,
        frame: CGRect?? = nil, reportedTabTitles: [String]? = nil
    ) -> Descriptor {
        Descriptor(
            id: id, title: title, isTabbed: isTabbed, groupIds: groupIds,
            frame: frame ?? groupFrame, reportedTabTitles: reportedTabTitles)
    }

    // MARK: - The canonical requirement

    /// Two browser windows with 5 tabs each must yield exactly 2 entries.
    /// Browsers expose one AX window per browser window: tab titles match no
    /// sibling window, so nothing is hidden and each window keeps its own count.
    @Test func twoSafariWindowsWithFiveTabsEachProduceTwoEntries() {
        let windowA = window("A", "Apple — Safari")
        let windowB = window("B", "News — Safari")
        let changesA = TabGroupResolver.resolve(
            active: windowA,
            observation: .group(["Apple — Safari", "Docs", "Mail", "Maps", "Music"]),
            sameAppWindows: [windowB])
        #expect(changesA["A"] == State(isTabbed: false, groupIds: ["A"]))
        #expect(changesA["B"] == nil, "the other Safari window must not be marked as a tab")
        let changesB = TabGroupResolver.resolve(
            active: windowB,
            observation: .group(["News — Safari", "Weather", "Stocks", "Notes", "Photos"]),
            sameAppWindows: [windowA])
        #expect(changesB["B"] == State(isTabbed: false, groupIds: ["B"]))
        #expect(changesB["A"] == nil)
        // net effect: A and B both untabbed → exactly 2 entries, each with its own count
    }

    // MARK: - Native window tabs (Finder/Terminal style)

    /// With native NSWindow tabs every tab is a real AX window; only siblings whose
    /// titles match the active tab bar's titles are hidden.
    @Test func nativeTabSiblingsAreMarkedTabbed() {
        let active = window("A", "Documents")
        let sibling1 = window("B", "Downloads")
        let sibling2 = window("C", "Desktop")
        let unrelated = window("D", "Pictures")
        let changes = TabGroupResolver.resolve(
            active: active,
            observation: .group(["Documents", "Downloads", "Desktop"]),
            sameAppWindows: [sibling1, sibling2, unrelated])
        #expect(changes["A"] == State(isTabbed: false, groupIds: ["A", "B", "C"]))
        #expect(changes["B"] == State(isTabbed: true, groupIds: ["A", "B", "C"]))
        #expect(changes["C"] == State(isTabbed: true, groupIds: ["A", "B", "C"]))
        #expect(changes["D"] == nil, "windows outside the group are untouched")
    }

    @Test func duplicateTabTitlesMatchDistinctSiblings() {
        let active = window("A", "untitled")
        let sibling1 = window("B", "untitled")
        let sibling2 = window("C", "untitled")
        let changes = TabGroupResolver.resolve(
            active: active,
            observation: .group(["untitled", "untitled", "untitled"]),
            sameAppWindows: [sibling1, sibling2])
        #expect(changes["B"]?.isTabbed == true)
        #expect(changes["C"]?.isTabbed == true)
        #expect(changes["A"]?.groupIds?.count == 3)
    }

    @Test func switchingActiveTabSwapsRoles() {
        // B was an inactive tab; the user selects it natively and it now reports the group
        let former = window("A", "Documents", isTabbed: false, groupIds: ["A", "B"])
        let nowActive = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(
            active: nowActive,
            observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [former])
        #expect(changes["B"] == State(isTabbed: false, groupIds: ["B", "A"]))
        #expect(changes["A"] == State(isTabbed: true, groupIds: ["B", "A"]))
    }

    // MARK: - Group dissolution

    @Test func activeWindowLeavingGroupIsCleared() {
        // a window that was a group's active tab now reports no tab bar (tab dragged out)
        let active = window("A", "Documents", isTabbed: false, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(
            active: active, observation: .standalone,
            sameAppWindows: [])
        #expect(changes["A"] == State(isTabbed: false, groupIds: nil))
    }

    @Test func inactiveTabReportingNilStaysTabbed() {
        // inactive tabs have no AXTabGroup child; a title-change event on one must
        // not clear its tabbed state
        let inactive = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolve(
            active: inactive, observation: .standalone,
            sameAppWindows: [])
        #expect(changes.isEmpty)
    }

    // MARK: - Detached tabs (#82)

    /// Measured sequence: Move Tab to New Window on A's active tab. B (the remaining,
    /// formerly inactive tab) reports standalone first, unmoved; then A, moved out.
    @Test func twoTabGroupDissolvesWhenItsActiveTabReportsStandalone() {
        let movedOut = window("A", "Untitled", groupIds: ["A", "B"], frame: otherFrame)
        let remaining = window("B", "Untitled 2", isTabbed: true, groupIds: ["A", "B"])
        let first = TabGroupResolver.resolve(
            active: remaining, observation: .standalone,
            sameAppWindows: [window("A", "Untitled", groupIds: ["A", "B"])],
            isFocusEvent: true)
        #expect(first.isEmpty, "B's frame still equals the group's recorded frame")
        let second = TabGroupResolver.resolve(
            active: movedOut, observation: .standalone,
            sameAppWindows: [remaining])
        #expect(second["A"] == State(isTabbed: false, groupIds: nil))
        #expect(
            second["B"] == State(isTabbed: false, groupIds: nil),
            "a lone former tab is a window again")
    }

    @Test func detachedInactiveTabBecomesAnEntryOnFocusWithADifferentFrame() {
        let groupActive = window("A", "Documents", groupIds: ["A", "B", "C"])
        let dragged = window(
            "B", "Downloads", isTabbed: true, groupIds: ["A", "B", "C"],
            frame: otherFrame)
        let stays = window("C", "Desktop", isTabbed: true, groupIds: ["A", "B", "C"])
        let changes = TabGroupResolver.resolve(
            active: dragged, observation: .standalone,
            sameAppWindows: [groupActive, stays],
            isFocusEvent: true)
        #expect(changes["B"] == State(isTabbed: false, groupIds: nil))
        #expect(changes["A"] == State(isTabbed: false, groupIds: ["A", "C"]))
        #expect(changes["C"] == State(isTabbed: true, groupIds: ["A", "C"]))
    }

    @Test func transientStandaloneDuringTabSwitchKeepsTheGroup() {
        // an inactive tab reading no tab bar keeps the group unless it is focused
        // somewhere else: same frame, no focus event, or an unknown frame
        let groupActive = window("A", "Documents", groupIds: ["A", "B"])
        let sameFrame = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        #expect(
            TabGroupResolver.resolve(
                active: sameFrame, observation: .standalone,
                sameAppWindows: [groupActive],
                isFocusEvent: true
            ).isEmpty)
        let moved = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"], frame: otherFrame)
        #expect(
            TabGroupResolver.resolve(
                active: moved, observation: .standalone,
                sameAppWindows: [groupActive]
            ).isEmpty)
        let unknownFrame = window(
            "B", "Downloads", isTabbed: true, groupIds: ["A", "B"],
            frame: .some(nil))
        #expect(
            TabGroupResolver.resolve(
                active: unknownFrame, observation: .standalone,
                sameAppWindows: [groupActive],
                isFocusEvent: true
            ).isEmpty)
    }

    @Test func unknownObservationNeverDetaches() {
        let groupActive = window("A", "Documents", groupIds: ["A", "B"])
        let dragged = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"], frame: otherFrame)
        #expect(
            TabGroupResolver.resolve(
                active: dragged, observation: .unknown,
                sameAppWindows: [groupActive],
                isFocusEvent: true
            ).isEmpty)
        #expect(
            TabGroupResolver.resolve(
                active: groupActive, observation: .unknown,
                sameAppWindows: [dragged]
            ).isEmpty)
    }

    @Test func detachLeavesAnotherGroupIntact() {
        let activeOne = window("A", "Documents", groupIds: ["A", "B"])
        let inactiveOne = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let activeTwo = window("C", "Pictures", groupIds: ["C", "D"], frame: otherFrame)
        let inactiveTwo = window("D", "Music", isTabbed: true, groupIds: ["C", "D"], frame: otherFrame)
        let dissolved = TabGroupResolver.resolve(
            active: activeOne, observation: .standalone,
            sameAppWindows: [inactiveOne, activeTwo, inactiveTwo])
        #expect(Set(dissolved.keys) == ["A", "B"])
        let dragged = window(
            "B", "Downloads", isTabbed: true, groupIds: ["A", "B"],
            frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        let detached = TabGroupResolver.resolve(
            active: dragged, observation: .standalone,
            sameAppWindows: [activeOne, activeTwo, inactiveTwo],
            isFocusEvent: true)
        #expect(Set(detached.keys) == ["A", "B"])
    }

    @Test func staleGroupMembersAreCleared() {
        let active = window("A", "Documents")
        let formerSibling = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        // A now reports a tab bar that no longer includes B's title
        let changes = TabGroupResolver.resolve(
            active: active,
            observation: .group(["Documents", "Desktop"]),
            sameAppWindows: [formerSibling])
        #expect(changes["B"] == State(isTabbed: false, groupIds: nil))
    }

    // MARK: - Independent groups in one app

    /// Two established native tab groups in one app: refreshing one must not
    /// dissolve the other, or its inactive tab reappears as its own entry.
    @Test func refreshingOneGroupPreservesAnotherGroupInTheSameApp() {
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

        #expect(changes["B"] == State(isTabbed: true, groupIds: groupOne))
        #expect(changes["C"] == nil, "the other group's active tab must be untouched")
        #expect(changes["D"] == nil, "the other group's inactive tab must stay hidden")
        #expect(
            !isDisplayed(inactiveTwo, applying: changes),
            "D must remain excluded as an inactive tab")
    }

    /// The symmetric refresh must hold too, so neither group wins by ordering.
    @Test func refreshingTheOtherGroupPreservesTheFirst() {
        let groupOne = ["A", "B"]
        let groupTwo = ["C", "D"]
        let inactiveOne = window("B", "B", isTabbed: true, groupIds: groupOne, frame: otherFrame)
        let activeTwo = window("C", "C", groupIds: groupTwo)
        let inactiveTwo = window("D", "D", isTabbed: true, groupIds: groupTwo)

        let changes = TabGroupResolver.resolve(
            active: activeTwo,
            observation: .group(["C", "D"]),
            sameAppWindows: [
                window("A", "A", groupIds: groupOne, frame: otherFrame),
                inactiveOne, inactiveTwo,
            ])

        #expect(changes["D"] == State(isTabbed: true, groupIds: groupTwo))
        #expect(changes["A"] == nil)
        #expect(changes["B"] == nil)
        #expect(!isDisplayed(inactiveOne, applying: changes))
    }

    /// A window that truly leaves the refreshed group still gets cleared, while
    /// an unrelated group in the same app survives the same update.
    @Test func formerMemberIsClearedWithoutDisturbingAnotherGroup() {
        let groupOne = ["A", "B"]
        let groupTwo = ["C", "D"]
        let formerSibling = window("B", "B", isTabbed: true, groupIds: groupOne)
        let inactiveTwo = window("D", "D", isTabbed: true, groupIds: groupTwo, frame: otherFrame)

        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: groupOne),
            observation: .group(["A"]),
            sameAppWindows: [
                formerSibling, window("C", "C", groupIds: groupTwo, frame: otherFrame),
                inactiveTwo,
            ])

        #expect(changes["B"] == State(isTabbed: false, groupIds: nil))
        #expect(
            isDisplayed(formerSibling, applying: changes),
            "B left the group and must become its own entry")
        #expect(changes["D"] == nil)
        #expect(!isDisplayed(inactiveTwo, applying: changes))
    }

    // MARK: - Title collisions (an independent window shares an inactive tab's title)

    /// Active A (Documents) with inactive tab B (Downloads), plus an independent
    /// window C also titled Downloads at another position. Listing C before B once
    /// hid C and left the real tab B visible.
    @Test func independentSameTitleWindowStaysVisibleWhenListedBeforeTheInactiveTab() {
        let (active, tab, independent) = collisionFixture()
        let changes = TabGroupResolver.resolve(
            active: active, observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [independent, tab])
        #expect(isDisplayed(independent, applying: changes))
        #expect(!isDisplayed(tab, applying: changes))
        #expect(changes["A"] == State(isTabbed: false, groupIds: ["A", "B"]))
    }

    @Test func independentSameTitleWindowStaysVisibleWhenListedAfterTheInactiveTab() {
        let (active, tab, independent) = collisionFixture()
        let changes = TabGroupResolver.resolve(
            active: active, observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [tab, independent])
        #expect(isDisplayed(independent, applying: changes))
        #expect(!isDisplayed(tab, applying: changes))
        #expect(changes["A"] == State(isTabbed: false, groupIds: ["A", "B"]))
    }

    private func collisionFixture() -> (Descriptor, Descriptor, Descriptor) {
        (
            window("A", "Documents"), window("B", "Downloads"),
            window("C", "Downloads", frame: otherFrame)
        )
    }

    @Test func duplicateTitleTabsSharingTheGroupFrameAreAllMatched() {
        let tabs = [window("B", "untitled"), window("C", "untitled")]
        let independent = window("D", "untitled", frame: otherFrame)
        for order in [tabs + [independent], [independent] + tabs.reversed()] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "untitled"),
                observation: .group(["untitled", "untitled", "untitled"]),
                sameAppWindows: order)
            #expect(!isDisplayed(tabs[0], applying: changes))
            #expect(!isDisplayed(tabs[1], applying: changes))
            #expect(isDisplayed(independent, applying: changes))
            #expect(Set(changes["A"]?.groupIds ?? []) == ["A", "B", "C"])
        }
    }

    /// Two unrecorded windows share the tab's title and the group's frame (say two
    /// maximized windows), but the tab bar holds that title once: nothing tells
    /// them apart, so neither is hidden.
    @Test func sameTitleSameFrameTieLeavesCandidatesVisible() {
        let first = window("B", "Downloads")
        let second = window("C", "Downloads")
        for order in [[first, second], [second, first]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
                sameAppWindows: order)
            #expect(isDisplayed(first, applying: changes))
            #expect(isDisplayed(second, applying: changes))
            #expect(changes["A"] == State(isTabbed: false, groupIds: ["A"]))
        }
    }

    /// Recorded membership separates a tie: the window already in this group wins.
    @Test func recordedMemberWinsASameFrameTie() {
        let member = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let stranger = window("C", "Downloads")
        for order in [[member, stranger], [stranger, member]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents", groupIds: ["A", "B"]),
                observation: .group(["Documents", "Downloads"]), sameAppWindows: order)
            #expect(!isDisplayed(member, applying: changes))
            #expect(isDisplayed(stranger, applying: changes))
        }
    }

    /// The active tab of another group shows its own tab bar; it is never taken
    /// as an inactive tab here, even with a matching title and frame.
    @Test func anotherGroupsActiveTabIsNeverMatched() {
        let otherActive = window("C", "Downloads", groupIds: ["C", "D"])
        let otherTab = window("D", "Music", isTabbed: true, groupIds: ["C", "D"])
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [otherActive, otherTab])
        #expect(changes["C"] == nil)
        #expect(isDisplayed(otherActive, applying: changes))
        #expect(!isDisplayed(otherTab, applying: changes))
    }

    @Test func unknownFrameRanksBelowAFrameEqualCandidate() {
        let tab = window("B", "Downloads")
        let unknown = window("C", "Downloads", frame: .some(nil))
        for order in [[unknown, tab], [tab, unknown]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
                sameAppWindows: order)
            #expect(!isDisplayed(tab, applying: changes))
            #expect(isDisplayed(unknown, applying: changes))
        }
    }

    /// Without any frame-equal candidate, a single unknown-frame title match is
    /// still the tab: geometry that cannot be read must not break grouping.
    @Test func aSingleUnknownFrameCandidateIsStillMatched() {
        let unknown = window("B", "Downloads", frame: .some(nil))
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [unknown])
        #expect(!isDisplayed(unknown, applying: changes))
    }

    /// Measured on macOS 26: after Window ▸ Merge All Windows an inactive tab keeps
    /// reporting its pre-merge frame. A different frame ranks last but does not
    /// exclude the only candidate, or every freshly merged tab would leak out.
    @Test func mergedTabWithStalePreMergeFrameIsStillMatched() {
        let stale = window("B", "Downloads", frame: otherFrame)
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [stale])
        #expect(!isDisplayed(stale, applying: changes))
    }

    /// Two same-title candidates whose frames both differ from the group's (a stale
    /// merged tab and an independent window) cannot be told apart: both stay visible.
    @Test func twoDifferentFrameCandidatesForOneTitleStayVisible() {
        let stale = window("B", "Downloads", frame: otherFrame)
        let independent = window("C", "Downloads", frame: otherFrame.offsetBy(dx: 40, dy: 40))
        for order in [[stale, independent], [independent, stale]] {
            let changes = TabGroupResolver.resolve(
                active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
                sameAppWindows: order)
            #expect(isDisplayed(stale, applying: changes))
            #expect(isDisplayed(independent, applying: changes))
        }
    }

    /// Frames are compared in whole points; sub-point AX noise is not a new window.
    @Test func subPointFrameDifferenceStillMatches() {
        let nudged = window("B", "Downloads", frame: groupFrame.offsetBy(dx: 0.3, dy: -0.2))
        let changes = TabGroupResolver.resolve(
            active: window("A", "Documents"), observation: .group(["Documents", "Downloads"]),
            sameAppWindows: [nudged])
        #expect(!isDisplayed(nudged, applying: changes))
    }

    // MARK: - Incomplete observations (a failed AX read is not evidence)

    @Test func failedTabTitleReadIsUnknown() {
        let observation = classify(tabGroup: [tab("A"), tab("B"), tab(title: .failed)])
        #expect(observation == .unknown)
    }

    @Test func failedTabSubroleReadIsUnknown() {
        let failedSubrole = TabObservation.TabButtonFacts(subrole: .failed, title: .value("C"))
        #expect(classify(tabGroup: [tab("A"), tab("B"), failedSubrole]) == .unknown)
    }

    @Test func failedChildrenReadIsUnknown() {
        #expect(TabObservation.classify(children: .failed) == .unknown)
        let failedTabBar = TabObservation.ChildFacts(role: .value("AXTabGroup"), tabs: .failed)
        #expect(TabObservation.classify(children: .value([failedTabBar])) == .unknown)
        let unreadableChild = TabObservation.ChildFacts(role: .failed, tabs: .failed)
        #expect(
            TabObservation.classify(children: .value([unreadableChild])) == .unknown,
            "an unreadable child could have been the tab bar")
    }

    @Test func noTabGroupIsStandalone() {
        let button = TabObservation.ChildFacts(role: .value("AXButton"), tabs: .absent)
        let roleless = TabObservation.ChildFacts(role: .absent, tabs: .absent)
        #expect(TabObservation.classify(children: .value([button, roleless])) == .standalone)
        #expect(TabObservation.classify(children: .value([])) == .standalone)
        #expect(TabObservation.classify(children: .absent) == .standalone)
        #expect(
            classify(tabGroup: [tab("A")]) == .standalone,
            "a tab bar with one tab is no group")
    }

    @Test func emptyTitleWithNoValueIsAGroupMember() {
        #expect(classify(tabGroup: [tab("A"), tab(title: .absent)]) == .group(["A", ""]))
    }

    @Test func nonTabButtonChildrenOfTheTabBarAreIgnored() {
        let addButton = TabObservation.TabButtonFacts(subrole: .value("AXButton"), title: .value("+"))
        let noSubrole = TabObservation.TabButtonFacts(subrole: .absent, title: .failed)
        #expect(
            classify(tabGroup: [tab("A"), addButton, noSubrole, tab("B")]) == .group(["A", "B"]))
    }

    /// A complete tab bar decides even when an unrelated child could not be read.
    @Test func completeTabBarDecidesDespiteAnUnreadableSibling() {
        let unreadable = TabObservation.ChildFacts(role: .failed, tabs: .failed)
        let tabBar = TabObservation.ChildFacts(
            role: .value("AXTabGroup"),
            tabs: .value([tab("A"), tab("B")]))
        #expect(
            TabObservation.classify(children: .value([unreadable, tabBar])) == .group(["A", "B"]))
    }

    /// A/B/C group; C's read fails while A and B succeed. The partial list used to
    /// be treated as complete and C was released as its own entry.
    @Test func unknownObservationKeepsAThreeMemberGroup() {
        let members = ["A", "B", "C"]
        let tabB = window("B", "B", isTabbed: true, groupIds: members)
        let tabC = window("C", "C", isTabbed: true, groupIds: members)
        let observation = classify(tabGroup: [tab("A"), tab("B"), tab(title: .failed)])
        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: members), observation: observation,
            sameAppWindows: [tabB, tabC])
        #expect(changes.isEmpty)
        #expect(!isDisplayed(tabB, applying: changes))
        #expect(!isDisplayed(tabC, applying: changes))
    }

    @Test func unknownObservationLeavesUnrelatedGroupsUntouched() {
        let otherTab = window("D", "D", isTabbed: true, groupIds: ["C", "D"], frame: otherFrame)
        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: ["A", "B"]), observation: .unknown,
            sameAppWindows: [
                window("B", "B", isTabbed: true, groupIds: ["A", "B"]),
                window("C", "C", groupIds: ["C", "D"], frame: otherFrame), otherTab,
            ])
        #expect(changes.isEmpty)
        #expect(!isDisplayed(otherTab, applying: changes))
    }

    /// The first complete read after a failed one restores the group: no restart,
    /// no retry timer.
    @Test func completeObservationAfterUnknownRecoversTheGroup() {
        let active = window("A", "A")
        let tabB = window("B", "B")
        let tabC = window("C", "C")
        let failed = TabGroupResolver.resolve(
            active: active, observation: .unknown,
            sameAppWindows: [tabB, tabC])
        #expect(failed.isEmpty)
        let recovered = TabGroupResolver.resolve(
            active: active, observation: .group(["A", "B", "C"]),
            sameAppWindows: [tabB, tabC])
        #expect(!isDisplayed(tabB, applying: recovered))
        #expect(!isDisplayed(tabC, applying: recovered))
        #expect(recovered["A"] == State(isTabbed: false, groupIds: ["A", "B", "C"]))
    }

    /// A complete read that no longer lists C still releases C: only incomplete
    /// reads are ignored.
    @Test func completeObservationStillRemovesADepartedMember() {
        let members = ["A", "B", "C"]
        let tabC = window("C", "C", isTabbed: true, groupIds: members)
        let changes = TabGroupResolver.resolve(
            active: window("A", "A", groupIds: members), observation: .group(["A", "B"]),
            sameAppWindows: [window("B", "B", isTabbed: true, groupIds: members), tabC])
        #expect(changes["C"] == State(isTabbed: false, groupIds: nil))
        #expect(isDisplayed(tabC, applying: changes))
        #expect(changes["A"] == State(isTabbed: false, groupIds: ["A", "B"]))
    }

    private func tab(_ title: String) -> TabObservation.TabButtonFacts {
        tab(title: .value(title))
    }

    private func tab(title: AttributeRead<String>) -> TabObservation.TabButtonFacts {
        TabObservation.TabButtonFacts(subrole: .value("AXTabButton"), title: title)
    }

    /// A window whose only child is a tab bar holding `tabs`.
    private func classify(tabGroup tabs: [TabObservation.TabButtonFacts]) -> TabObservation {
        TabObservation.classify(
            children: .value([
                TabObservation.ChildFacts(role: .value("AXTabGroup"), tabs: .value(tabs))
            ]))
    }

}

extension TabGroupResolverTests {
    // MARK: - Discovery order (an active tab can be discovered before its siblings)

    @Test func inactiveSiblingArrivingAfterItsActiveTabIsHidden() {
        let store = discover([activeArrival("A", tabs: ["A", "B"]), inactiveArrival("B")])
        #expect(visibleIds(store) == ["A"])
        #expect(store["B"]?.groupIds.map(Set.init) == ["A", "B"])
    }

    @Test func activeTabArrivingAfterItsInactiveSiblingHidesIt() {
        let store = discover([inactiveArrival("B"), activeArrival("A", tabs: ["A", "B"])])
        #expect(visibleIds(store) == ["A"])
        #expect(store["B"]?.groupIds.map(Set.init) == ["A", "B"])
    }

    /// Resolving the arrival directly: only the waiting group changes.
    @Test func arrivalOfAnUnrelatedTitleChangesNothing() {
        let active = window("A", "A", groupIds: ["A"], reportedTabTitles: ["A", "B"])
        let changes = TabGroupResolver.resolveArrival(
            newWindow: window("X", "Unrelated"),
            sameAppWindows: [active])
        #expect(changes.isEmpty)
    }

    /// A complete group (nothing unmatched) is not re-resolved when a window with
    /// one of its titles arrives: the newcomer stays visible and the group intact.
    @Test func arrivalDoesNotDisturbAnotherCompleteGroup() {
        let members = ["C", "D"]
        let completeActive = window("C", "C", groupIds: members, reportedTabTitles: ["C", "D"])
        let completeTab = window("D", "D", isTabbed: true, groupIds: members)
        let waitingActive = window(
            "A", "A", groupIds: ["A"], frame: otherFrame,
            reportedTabTitles: ["A", "B"])
        let newcomer = window("B", "B", frame: otherFrame)
        let lookalike = window("E", "D")
        for others in [
            [completeActive, completeTab, waitingActive],
            [waitingActive, completeTab, completeActive],
        ] {
            let changes = TabGroupResolver.resolveArrival(newWindow: newcomer, sameAppWindows: others)
            #expect(changes["B"] == State(isTabbed: true, groupIds: ["A", "B"]))
            #expect(changes["C"] == nil)
            #expect(changes["D"] == nil)
            let lookalikeChanges = TabGroupResolver.resolveArrival(
                newWindow: lookalike,
                sameAppWindows: others)
            #expect(lookalikeChanges.isEmpty, "C's group has no unmatched title")
        }
    }

    /// Startup enumeration returns windows in arbitrary order (Array(Set(...))).
    /// Every order of one active tab and two inactive siblings, plus an
    /// independent window, yields one entry for the group.
    @Test func startupEnumerationInEitherOrderYieldsOneEntry() {
        let arrivals = [
            activeArrival("A", tabs: ["A", "B", "C"]), inactiveArrival("B"),
            inactiveArrival("C"), inactiveArrival("X", frame: otherFrame),
        ]
        for order in permutations(arrivals) {
            let store = discover(order)
            #expect(visibleIds(store) == ["A", "X"], "order \(order.map(\.id))")
            #expect(store["A"]?.groupIds.map(Set.init) == ["A", "B", "C"])
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
            // `apply` keeps the order, so the arrival stays at this index
            let arrivalIndex = store.count
            store.append(
                window(
                    arrival.id, arrival.id, frame: arrival.frame,
                    reportedTabTitles: reported))
            let newWindow = { store[arrivalIndex] }
            let others = { store.filter { $0.id != arrival.id } }
            if case .group = arrival.observation {
                apply(
                    TabGroupResolver.resolve(
                        active: newWindow(), observation: arrival.observation,
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
    private func isDisplayed(
        _ descriptor: Descriptor,
        applying changes: [String: State]
    ) -> Bool {
        let isTabbed = changes[descriptor.id]?.isTabbed ?? descriptor.isTabbed
        return WindowEligibility.shouldDisplay(
            WindowDisplayState(
                isMinimized: false, isAppHidden: false, isOwnWindow: false,
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
    @Test func sessionRereadAfterALiveMergeYieldsOneEntryInAnyOrder() throws {
        let reads: [(id: String, observation: TabObservation)] = [
            ("A", .group(["A", "C", "B"])), ("B", .standalone), ("C", .standalone),
        ]
        for order in permutations(reads) {
            var store = [
                window("A", "A"),
                window("B", "B", frame: otherFrame),
                window("C", "C", frame: otherFrame.offsetBy(dx: -29, dy: -29)),
            ]
            for read in order {
                var reread = try #require(store.first { $0.id == read.id })
                if case .group(let titles) = read.observation {
                    reread = window(
                        reread.id, reread.title, isTabbed: reread.isTabbed,
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
            #expect(visible == ["A"], "order \(order.map(\.id))")
            #expect(store.first?.groupIds.map(Set.init) == ["A", "B", "C"])
        }
    }

    @Test func sessionRereadTargetsOnlyAppsWithTwoOrMoreEntries() {
        let entries: [(id: String, appId: String?)] = [
            ("te1", "TextEdit"), ("safari", "Safari"), ("te2", "TextEdit"),
            ("settings", nil), ("te3", "TextEdit"),
        ]
        #expect(TabGroupResolver.sessionRereadTargets(entries) == ["te1", "te2", "te3"])
    }

    @Test func sessionRereadTargetsNothingWhenEveryAppHasOneEntry() {
        let entries: [(id: String, appId: String?)] = [
            ("te", "TextEdit"), ("safari", "Safari"), ("settings", nil), ("other", nil),
        ]
        #expect(TabGroupResolver.sessionRereadTargets(entries).isEmpty)
    }

    // MARK: - Removal

    @Test func removalShrinksGroup() {
        let b = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B", "C"])
        let c = window("C", "Desktop", isTabbed: true, groupIds: ["A", "B", "C"])
        let changes = TabGroupResolver.resolveRemoval(
            removedId: "A",
            groupIds: ["A", "B", "C"],
            remainingWindows: [b, c])
        #expect(changes["B"] == State(isTabbed: true, groupIds: ["B", "C"]))
        #expect(changes["C"] == State(isTabbed: true, groupIds: ["B", "C"]))
    }

    @Test func removalDownToOneClearsTabState() {
        let b = window("B", "Downloads", isTabbed: true, groupIds: ["A", "B"])
        let changes = TabGroupResolver.resolveRemoval(
            removedId: "A",
            groupIds: ["A", "B"],
            remainingWindows: [b])
        #expect(changes["B"] == State(isTabbed: false, groupIds: nil))
    }

    // MARK: - Display rule

    @Test func tabbedWindowsAreNeverDisplayed() {
        let state = WindowDisplayState(
            isMinimized: false, isAppHidden: false,
            isOwnWindow: false, isTabbed: true,
            isOnCurrentSpace: true, isOnActiveDisplay: true)
        #expect(!WindowEligibility.shouldDisplay(state, policy: .init()))
    }
}
