import Foundation

/// Decides which windows are really inactive tabs of a native tab group, so tabs
/// never become independent switcher entries. Ported from AltTab v10.12.0's
/// TabGroup.updateState, with AXUIElement identity instead of CGWindowIDs.
///
/// Background: with native macOS window tabs (Finder, Terminal, TextEdit, …) every
/// tab is a real AX window. Only the visible tab exposes the AXTabGroup child with
/// one AXTabButton per tab. Inactive tabs are matched by title within the same app
/// and hidden; when the user selects another tab natively, that window becomes the
/// group's active tab and the roles swap. Browsers with custom tabs (Safari, Chrome)
/// expose one AX window per browser window, so nothing matches and nothing is hidden.
public enum TabGroupResolver {
    /// What the resolver knows about one same-app window.
    public struct WindowDescriptor<ID: Hashable> {
        public let id: ID
        public let title: String
        public let isTabbed: Bool
        public let groupIds: [ID]?
        /// The window's AX frame, when known. Native tabs of one window share its frame.
        public let frame: CGRect?
        /// The titles of the window's last complete tab bar read (`.group`), if any.
        public let reportedTabTitles: [String]?

        public init(id: ID, title: String, isTabbed: Bool, groupIds: [ID]?, frame: CGRect?,
                    reportedTabTitles: [String]?) {
            self.id = id
            self.title = title
            self.isTabbed = isTabbed
            self.groupIds = groupIds
            self.frame = frame
            self.reportedTabTitles = reportedTabTitles
        }

        func applying(_ change: WindowTabState<ID>?) -> WindowDescriptor<ID> {
            guard let change else { return self }
            return WindowDescriptor(id: id, title: title, isTabbed: change.isTabbed,
                                    groupIds: change.groupIds, frame: frame,
                                    reportedTabTitles: reportedTabTitles)
        }
    }

    /// The new tab state for one window.
    public struct WindowTabState<ID: Hashable>: Equatable {
        public let isTabbed: Bool
        public let groupIds: [ID]?

        public init(isTabbed: Bool, groupIds: [ID]?) {
            self.isTabbed = isTabbed
            self.groupIds = groupIds
        }
    }

    /// A window (`active`) was just observed (see `TabObservation`).
    /// `sameAppWindows` are the other windows of the same app. `isFocusEvent` is true
    /// when the observation came with a focused- or main-window notification.
    /// Returns per-window state changes; windows not in the result are unchanged.
    public static func resolve<ID: Hashable>(
        active: WindowDescriptor<ID>,
        observation: TabObservation,
        sameAppWindows: [WindowDescriptor<ID>],
        isFocusEvent: Bool = false
    ) -> [ID: WindowTabState<ID>] {
        var changes = [ID: WindowTabState<ID>]()
        let tabTitles: [String]
        switch observation {
        case .unknown:
            // missing evidence is not an observation: a partial read must never
            // shrink or dissolve a known group (upstream 8c8d2836 draws the same line)
            return changes
        case .standalone:
            return resolveStandalone(active: active, sameAppWindows: sameAppWindows,
                                     isFocusEvent: isFocusEvent)
        case .group(let titles):
            tabTitles = titles
        }
        // one tab title belongs to the active window itself; remove one occurrence
        // (not all — different tabs can share a title)
        var remainingTitles = tabTitles
        if let index = remainingTitles.firstIndex(of: active.title) {
            remainingTitles.remove(at: index)
        }
        let matched = matchSiblings(of: active, titles: remainingTitles,
                                    sameAppWindows: sameAppWindows)
        let groupIds = [active.id] + matched.map { $0.id }
        changes[active.id] = WindowTabState(isTabbed: false, groupIds: groupIds)
        for sibling in matched {
            changes[sibling.id] = WindowTabState(isTabbed: true, groupIds: groupIds)
        }
        // Windows that used to be in *this* group but no longer are. Membership is
        // read from the candidate, not from `active.groupIds`, because the active
        // window's own membership may not have been recorded yet. AltTab v10.12.0
        // cleared every same-app window with any group, which also dissolved the
        // app's other, unrelated tab groups.
        for window in sameAppWindows
        where window.id != active.id
            && !matched.contains(where: { $0.id == window.id })
            && window.groupIds?.contains(active.id) == true {
            changes[window.id] = WindowTabState(isTabbed: false, groupIds: nil)
        }
        return changes
    }

    /// A complete read found no tab bar. Inactive tabs have none either, so this alone
    /// proves nothing about an inactive tab; two facts show that a tab left its group.
    /// Measured for #82 on macOS 26 (TextEdit, Window ▸ Move Tab to New Window on the
    /// active tab of a two-tab group): the remaining, formerly inactive tab reports
    /// standalone first, with its frame unchanged, then the moved-out tab reports
    /// standalone; the remaining window used to stay hidden as a tab.
    /// 1. The group's active tab reports standalone: its tab bar is gone, so every
    ///    member recorded with it is released. A group that still exists is formed
    ///    again by its new active tab's next tab bar read.
    /// 2. An inactive tab is focused and its frame differs from its group's active tab:
    ///    it was dragged out into a window of its own. It leaves, and the old group
    ///    shrinks as if the window had closed.
    /// Anything else keeps the state: upstream 0af8eb3d measured a momentary
    /// standalone during a tab switch and confirms detachment with private Space
    /// facts; focus and frame are their public stand-ins here.
    private static func resolveStandalone<ID: Hashable>(
        active: WindowDescriptor<ID>,
        sameAppWindows: [WindowDescriptor<ID>],
        isFocusEvent: Bool
    ) -> [ID: WindowTabState<ID>] {
        var changes = [ID: WindowTabState<ID>]()
        guard let groupIds = active.groupIds else { return changes }
        if !active.isTabbed {
            changes[active.id] = WindowTabState(isTabbed: false, groupIds: nil)
            for window in sameAppWindows where window.groupIds?.contains(active.id) == true {
                changes[window.id] = WindowTabState(isTabbed: false, groupIds: nil)
            }
            return changes
        }
        guard isFocusEvent,
              let groupActive = sameAppWindows.first(where: { groupIds.contains($0.id) && !$0.isTabbed }),
              let frame = active.frame, let groupFrame = groupActive.frame,
              rounded(frame) != rounded(groupFrame) else { return changes }
        changes[active.id] = WindowTabState(isTabbed: false, groupIds: nil)
        changes.merge(resolveRemoval(removedId: active.id, groupIds: groupIds,
                                     remainingWindows: sameAppWindows)) { _, new in new }
        return changes
    }

    /// Which same-app windows are the inactive tabs behind `titles`. A title match
    /// alone is not proof: an independent window can share an inactive tab's title,
    /// and AltTab v10.12.0's first-match rule could hide it. Candidates are ranked by
    /// facts, never by their position in `sameAppWindows`:
    /// 1. native tabs share their window's frame, so a frame equal to the active
    ///    tab's ranks first, an unknown frame second, and a different frame last
    ///    (upstream ae89aefa relies on the same geometry rule). A different frame is
    ///    not excluded outright: measured on macOS 26 (TextEdit, Window ▸ Merge All
    ///    Windows), a merged inactive tab keeps reporting its pre-merge AX frame and
    ///    emits no moved/resized notification, so exclusion would leak real tabs;
    /// 2. within one frame rank, recorded members of this group come first.
    /// Each rank class is taken whole or not at all. When a class holds more windows
    /// than titles still to fill, the facts cannot tell them apart, so none of them is
    /// matched: an ambiguous window stays a visible entry instead of being hidden by
    /// a guess.
    private static func matchSiblings<ID: Hashable>(
        of active: WindowDescriptor<ID>,
        titles: [String],
        sameAppWindows: [WindowDescriptor<ID>]
    ) -> [WindowDescriptor<ID>] {
        var matched = [WindowDescriptor<ID>]()
        var handledTitles = Set<String>()
        for title in titles where !handledTitles.contains(title) {
            handledTitles.insert(title)
            var needed = titles.filter { $0 == title }.count
            let candidates = sameAppWindows.filter { candidate in
                candidate.id != active.id && candidate.title == title
                    && !ownsAnotherTabBar(candidate, active: active)
            }
            let order = [(0, true), (0, false), (1, true), (1, false), (2, true), (2, false)]
            let rankClasses = order.map { rank, isMember in
                candidates.filter {
                    frameRank($0, active: active) == rank
                        && ($0.groupIds?.contains(active.id) == true) == isMember
                }
            }
            for rankClass in rankClasses where !rankClass.isEmpty {
                guard rankClass.count <= needed else { break }
                matched += rankClass
                needed -= rankClass.count
            }
        }
        return matched
    }

    /// The active tab of a *different* recorded group shows its own tab bar, so it
    /// cannot be an inactive tab here.
    private static func ownsAnotherTabBar<ID: Hashable>(
        _ candidate: WindowDescriptor<ID>, active: WindowDescriptor<ID>
    ) -> Bool {
        guard let groupIds = candidate.groupIds else { return false }
        return groupIds.count > 1 && !candidate.isTabbed && !groupIds.contains(active.id)
    }

    /// 0: the active tab's frame; 1: either frame unknown; 2: a different frame.
    /// AX frames are compared rounded to whole points.
    private static func frameRank<ID: Hashable>(
        _ candidate: WindowDescriptor<ID>, active: WindowDescriptor<ID>
    ) -> Int {
        guard let candidateFrame = candidate.frame, let activeFrame = active.frame else { return 1 }
        return rounded(candidateFrame) == rounded(activeFrame) ? 0 : 2
    }

    private static func rounded(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.origin.x.rounded(), y: frame.origin.y.rounded(),
               width: frame.width.rounded(), height: frame.height.rounded())
    }

    /// A window (`newWindow`, already resolved on its own) was just discovered.
    /// Discovery order is arbitrary: an active tab can be resolved before its inactive
    /// sibling exists in the store, and the sibling's own read shows no tab bar. So
    /// every active tab whose last complete tab bar still has an unmatched title equal
    /// to the new window's title is resolved again with the new window present.
    /// Groups with nothing unmatched are not touched, which keeps unrelated groups
    /// intact. `sameAppWindows` are the app's other windows; the result is sparse.
    public static func resolveArrival<ID: Hashable>(
        newWindow: WindowDescriptor<ID>,
        sameAppWindows: [WindowDescriptor<ID>]
    ) -> [ID: WindowTabState<ID>] {
        var changes = [ID: WindowTabState<ID>]()
        var windows = [newWindow] + sameAppWindows
        for (index, window) in windows.enumerated() where index > 0 {
            // earlier re-resolutions may have changed this window
            let current = window.applying(changes[window.id])
            guard !current.isTabbed, let titles = current.reportedTabTitles,
                  (current.groupIds?.count ?? 1) < titles.count,
                  unmatchedTitles(of: current, titles: titles, among: windows)
                      .contains(newWindow.title) else { continue }
            let others = windows.filter { $0.id != current.id }
            let resolved = resolve(active: current, observation: .group(titles),
                                   sameAppWindows: others)
            changes.merge(resolved) { _, new in new }
            windows = windows.map { $0.applying(resolved[$0.id]) }
            // the new window belongs to at most one group
            if resolved[newWindow.id]?.isTabbed == true { break }
        }
        return changes
    }

    /// `titles` minus one occurrence for the active window and for each recorded member.
    private static func unmatchedTitles<ID: Hashable>(
        of active: WindowDescriptor<ID>, titles: [String], among windows: [WindowDescriptor<ID>]
    ) -> [String] {
        var remaining = titles
        let memberIds = Set(active.groupIds ?? []).subtracting([active.id])
        let memberTitles = [active.title] + windows.filter { memberIds.contains($0.id) }.map(\.title)
        for title in memberTitles {
            if let index = remaining.firstIndex(of: title) {
                remaining.remove(at: index)
            }
        }
        return remaining
    }

    /// Which session entries to re-read when a switcher session opens. Measured on
    /// macOS 26 (TextEdit, Window ▸ Merge All Windows): a live merge sends none of
    /// the notifications WindowHop observes, so the new tab bar is only seen on the
    /// next read. A merge needs two or more windows of one app, so only entries whose
    /// app shows at least two of them can be hiding a tab; everything else is skipped.
    /// Entries without an app (the own Settings window) are never re-read.
    public static func sessionRereadTargets<ID: Hashable, AppID: Hashable>(
        _ entries: [(id: ID, appId: AppID?)]
    ) -> [ID] {
        var counts = [AppID: Int]()
        for entry in entries {
            if let appId = entry.appId { counts[appId, default: 0] += 1 }
        }
        return entries.compactMap { entry in
            guard let appId = entry.appId, counts[appId, default: 0] >= 2 else { return nil }
            return entry.id
        }
    }

    /// A window disappeared; shrink its group. A group of one is no group at all.
    public static func resolveRemoval<ID: Hashable>(
        removedId: ID,
        groupIds: [ID],
        remainingWindows: [WindowDescriptor<ID>]
    ) -> [ID: WindowTabState<ID>] {
        var changes = [ID: WindowTabState<ID>]()
        let remainingIds = groupIds.filter { $0 != removedId }
        let members = remainingWindows.filter { remainingIds.contains($0.id) }
        if members.count <= 1 {
            for member in members {
                changes[member.id] = WindowTabState(isTabbed: false, groupIds: nil)
            }
        } else {
            for member in members {
                changes[member.id] = WindowTabState(isTabbed: member.isTabbed, groupIds: remainingIds)
            }
        }
        return changes
    }
}
