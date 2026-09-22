import Foundation

/// Canonical public project destinations used by native About UI. Keeping
/// these URLs together prevents attribution, support, and website links from
/// drifting independently across panes.
public enum ProjectLinks {
    public static let website = URL(string: "https://windowhop.martonpaulo.com/")!
    public static let repository = URL(string: "https://github.com/martonpaulo/windowhop")!
    public static let releases = URL(string: "https://github.com/martonpaulo/windowhop/releases")!
    public static let altTabRepository = URL(string: "https://github.com/lwouis/alt-tab-macos")!

    /// The bug-report issue form and the ids of the inputs this link fills in.
    /// `scripts/validate.sh` checks that `.github/ISSUE_TEMPLATE/bug_report.yml`
    /// still declares both ids, so renaming a field cannot silently drop the
    /// prefill.
    static let bugReportTemplate = "bug_report.yml"
    static let windowHopVersionField = "windowhop-version"
    static let macOSVersionField = "macos-version"

    /// "Report an Issue…": the public bug-report form with the app version,
    /// build, release date and macOS version filled in. The repository uses
    /// YAML issue forms with blank issues disabled, so fields are prefilled by
    /// their `id` as query parameters (a plain `body=` would be dropped):
    /// https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema
    ///
    /// Only public build metadata and the macOS version are sent: no window
    /// titles, paths, hardware, account or machine identifiers. Opening the URL
    /// shows the form in the browser; the person reviews and submits it.
    public static func issueReport(for version: AppVersion,
                                   macOS: OperatingSystemVersion) -> URL {
        var components = URLComponents(string: "https://github.com/martonpaulo/windowhop/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: bugReportTemplate),
            URLQueryItem(name: windowHopVersionField, value: reportedVersion(version)),
            URLQueryItem(name: macOSVersionField, value: reportedMacOS(macOS)),
        ]
        return components.url!
    }

    /// "1.6.2 (build 10602, released 2026-09-15)". The date is the unlocalized
    /// ISO form so a report reads the same in every language, and it is left
    /// out when the build has none, never replaced by today's date.
    static func reportedVersion(_ version: AppVersion) -> String {
        guard let number = version.version else { return version.displayVersion }
        var details: [String] = []
        if let build = version.build, build != number {
            details.append("build \(build)")
        }
        if let released = version.releaseDateISO {
            details.append("released \(released)")
        }
        return details.isEmpty ? number : "\(number) (\(details.joined(separator: ", ")))"
    }

    /// "macOS 26.6.2", or "macOS 26.6" when there is no patch number.
    static func reportedMacOS(_ macOS: OperatingSystemVersion) -> String {
        var text = "macOS \(macOS.majorVersion).\(macOS.minorVersion)"
        if macOS.patchVersion != 0 {
            text += ".\(macOS.patchVersion)"
        }
        return text
    }
}
