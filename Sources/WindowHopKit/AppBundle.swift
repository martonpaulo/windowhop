import Foundation

/// Facts about the bundle the process runs from.
public enum AppBundle {
    /// A real application bundle: `…/Something.app` with an identifier. The
    /// extension alone is not enough — a directory can be named `x.app`. The
    /// unbundled `swift build` binary is not one.
    public static func isApplication(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app" && bundle.bundleIdentifier != nil
    }
}
