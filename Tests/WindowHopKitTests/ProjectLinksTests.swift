import Foundation
import Testing

@testable import WindowHopKit

/// "Report an Issue…" opens the public bug-report form with public build
/// metadata and the macOS version filled in, and nothing else.
struct ProjectLinksTests {
    private let macOS = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 2)

    private func version(date: String? = "2026-09-15") -> AppVersion {
        var info: [String: Any] = ["CFBundleShortVersionString": "1.6.2", "CFBundleVersion": "10602"]
        info["AppReleaseDate"] = date
        return AppVersion(infoDictionary: info)
    }

    private func queryItems(_ url: URL) throws -> [URLQueryItem] {
        try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    @Test func packagedBuildPrefillsTheBugReportForm() throws {
        let url = ProjectLinks.issueReport(for: version(), macOS: macOS)
        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path == "/martonpaulo/windowhop/issues/new")
        #expect(
            try queryItems(url) == [
                URLQueryItem(name: "template", value: "bug_report.yml"),
                URLQueryItem(name: "windowhop-version", value: "1.6.2 (build 10602, released 2026-09-15)"),
                URLQueryItem(name: "macos-version", value: "macOS 26.6.2"),
            ])
    }

    @Test func missingReleaseDateIsLeftOut() throws {
        let items = try queryItems(ProjectLinks.issueReport(for: version(date: nil), macOS: macOS))
        #expect(items.first { $0.name == "windowhop-version" }?.value == "1.6.2 (build 10602)")
    }

    @Test func developmentBuildSaysSo() throws {
        let items = try queryItems(
            ProjectLinks.issueReport(
                for: AppVersion(infoDictionary: [:]),
                macOS: macOS))
        #expect(items.first { $0.name == "windowhop-version" }?.value == "Development build")
    }

    @Test func macOSWithoutPatchNumber() {
        #expect(
            ProjectLinks.reportedMacOS(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) == "macOS 26.0")
    }

    @Test func spacesAndParenthesesArePercentEncoded() {
        let query = ProjectLinks.issueReport(for: version(), macOS: macOS).query ?? ""
        #expect(!query.contains(" "), "\(query)")
        #expect(query.contains("macOS%2026.6.2"), "\(query)")
        #expect(
            query.contains("1.6.2%20(build%2010602,%20released%202026-09-15)")
                || query.contains("1.6.2%20%28build%2010602%2C%20released%202026-09-15%29"), "\(query)")
    }

    @Test func nothingBeyondTheThreeFields() throws {
        let items = try queryItems(ProjectLinks.issueReport(for: version(), macOS: macOS))
        #expect(items.map(\.name) == ["template", "windowhop-version", "macos-version"])
    }
}
