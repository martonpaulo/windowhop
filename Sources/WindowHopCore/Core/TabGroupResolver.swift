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

        public init(id: ID, title: String, isTabbed: Bool, groupIds: [ID]?) {
            self.id = id
            self.title = title
            self.isTabbed = isTabbed
            self.groupIds = groupIds
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
        var matched = [WindowDescriptor<ID>]()
        for title in remainingTitles {
            if let sibling = sameAppWindows.first(where: { candidate in
                candidate.id != active.id && candidate.title == title
                    && !matched.contains(where: { $0.id == candidate.id })
            }) {
                matched.append(sibling)
            }
        }
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
