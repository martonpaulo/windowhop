import Foundation

/// The one reader of the running build's public metadata: version, build,
/// release date and copyright. Settings › About (WindowHop's only About
/// surface), the Updates pane and support reports all show the same values
/// through it.
///
/// The release date is written into the packaged `Info.plist` under
/// `AppReleaseDate` by `scripts/stamp-app-metadata.sh`, as the packaged
/// commit's committer date (`YYYY-MM-DD`), so rebuilding a commit gives the
/// same value. It is never typed into `Support/Info.plist`, never computed at
/// launch and never derived from install or modification times. A build
/// without it (every `swift build` run) simply has no release date.
public struct AppVersion: Equatable, Sendable {
    public static let releaseDateKey = "AppReleaseDate"

    /// `CFBundleShortVersionString`; nil in an unbundled development build.
    public let version: String?
    /// `CFBundleVersion`.
    public let build: String?
    /// Midnight UTC of the release day; nil when absent or malformed.
    public let releaseDate: Date?
    /// `NSHumanReadableCopyright`, the canonical copyright and attribution
    /// line; nil in an unbundled development build, which embeds no Info.plist.
    public let copyright: String?

    public init(infoDictionary: [String: Any]) {
        version = Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"])
        build = Self.nonEmptyString(infoDictionary["CFBundleVersion"])
        releaseDate = Self.nonEmptyString(infoDictionary[Self.releaseDateKey])
            .flatMap(Self.parseReleaseDate)
        copyright = Self.nonEmptyString(infoDictionary["NSHumanReadableCopyright"])
    }

    /// The running app's metadata.
    public static var main: AppVersion {
        AppVersion(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// "1.6.2 (10602)"; the build is left out when it repeats the version.
    /// A build without a version is a development build, said honestly rather
    /// than with an invented number.
    public var displayVersion: String {
        guard let version else { return String(localized: "Development build") }
        guard let build, build != version else { return version }
        return "\(version) (\(build))"
    }

    /// A standalone label: "Version 1.6.2 (10602)", or "Development build".
    public var versionLabel: String {
        version == nil ? displayVersion : String(localized: "Version \(displayVersion)")
    }

    /// The release date as a long localized date, e.g. "September 15, 2026".
    /// Formatted in UTC because the stored value is midnight UTC: in a local
    /// time zone west of UTC it would read as the previous day.
    public func releaseDateText(locale: Locale = .current) -> String? {
        releaseDate?.formatted(
            Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: .gmt))
    }

    /// The unlocalized release date ("2026-09-15") for support reports, so a
    /// report reads the same whatever the reporter's language.
    public var releaseDateISO: String? {
        releaseDate?.formatted(Self.isoDateStyle)
    }

    // MARK: - Parsing

    private static let isoDateStyle = Date.ISO8601FormatStyle().year().month().day()

    /// Accepts exactly `YYYY-MM-DD`. The format style alone is lenient (it
    /// rolls "2026-02-30" over to March and accepts trailing times), so the
    /// value must also survive a round trip unchanged.
    private static func parseReleaseDate(_ text: String) -> Date? {
        guard let date = try? isoDateStyle.parse(text),
            isoDateStyle.format(date) == text
        else { return nil }
        return date
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
