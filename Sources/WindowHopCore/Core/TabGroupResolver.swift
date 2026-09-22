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

        public init(id: ID, title: String, isTabbed: Bool, groupIds: [ID]?, frame: CGRect?) {
            self.id = id
            self.title = title
            self.isTabbed = isTabbed
            self.groupIds = groupIds
            self.frame = frame
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

    /// A window (`active`) just reported its AXTabGroup tab titles (nil when it has
    /// no tab bar). `sameAppWindows` are the other windows of the same app.
    /// Returns per-window state changes; windows not in the result are unchanged.
    public static func resolve<ID: Hashable>(
        active: WindowDescriptor<ID>,
        tabTitles: [String]?,
        sameAppWindows: [WindowDescriptor<ID>]
    ) -> [ID: WindowTabState<ID>] {
        var changes = [ID: WindowTabState<ID>]()
        guard let tabTitles else {
            // inactive tabs also report nil (they have no AXTabGroup child) but are
            // still tabbed; only clear a window that was its group's *active* tab
            if active.groupIds != nil, !active.isTabbed {
                changes[active.id] = WindowTabState(isTabbed: false, groupIds: nil)
            }
            return changes
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
