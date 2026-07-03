import Foundation

/// Title fallback order, derived from AltTab's Window.bestEffortTitle:
/// 1. non-empty window title
/// 2. document name (last path component of the window's AXDocument)
/// 3. localized application name
public enum TitleResolver {
    public static func resolve(axTitle: String?, documentPath: String?, appName: String?) -> String {
        if let axTitle, !axTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axTitle
        }
        if let documentName = documentName(fromPath: documentPath), !documentName.isEmpty {
            return documentName
        }
        return appName ?? ""
    }

    static func documentName(fromPath path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.removingPercentEncoding ?? name
    }
}
