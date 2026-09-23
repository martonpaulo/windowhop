import Foundation

/// Display labels for entries that would otherwise look identical. When two or more
/// windows of the same app share a displayed title, each one whose `AXDocument` has a
/// parent folder gets " — <folder>" appended, as long as that folder actually tells the
/// group apart. Nothing is invented when no document separates them (two "Untitled"
/// windows stay "Untitled"), and array position is never used, so a label only depends
/// on the window's own metadata and survives MRU changes, additions and removals.
///
/// Presentation only: the raw title stays the value used for preview matching,
/// tab-group resolution and AX association.
public enum CollisionLabel {
    public static let separator = " — "

    public struct Entry<AppID: Hashable> {
        public let appId: AppID
        public let title: String
        /// The raw `AXDocument` value: a file URL string, or a plain path.
        public let documentPath: String?

        public init(appId: AppID, title: String, documentPath: String?) {
            self.appId = appId
            self.title = title
            self.documentPath = documentPath
        }
    }

    private struct GroupKey<AppID: Hashable>: Hashable {
        let appId: AppID
        let title: String
    }

    /// One label per entry, in input order.
    public static func labels<AppID: Hashable>(for entries: [Entry<AppID>]) -> [String] {
        let folders = entries.map { parentFolderName(of: $0.documentPath) }
        var groups: [GroupKey<AppID>: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            groups[GroupKey(appId: entry.appId, title: entry.title), default: []].append(index)
        }
        var labels = entries.map(\.title)
        for members in groups.values where members.count > 1 {
            // only qualify when the folders (a missing one counts as its own value)
            // actually tell the group apart
            guard Set(members.map { folders[$0] }).count > 1 else { continue }
            for index in members {
                if let folder = folders[index] {
                    labels[index] = entries[index].title + separator + folder
                }
            }
        }
        return labels
    }

    /// The name of the folder containing the document, or nil when there is none.
    static func parentFolderName(of documentPath: String?) -> String? {
        guard let documentPath, !documentPath.isEmpty else { return nil }
        let url: URL
        if let parsed = URL(string: documentPath), parsed.isFileURL {
            url = parsed
        } else if documentPath.hasPrefix("/") {
            url = URL(fileURLWithPath: documentPath)
        } else {
            return nil
        }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return nil }
        let name = parent.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
