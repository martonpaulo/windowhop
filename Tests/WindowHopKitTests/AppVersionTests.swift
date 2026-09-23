import Foundation
import Testing

@testable import WindowHopKit

/// About, Updates and support reports show the version, build and release
/// date through `AppVersion`. A missing or bad release date must never hide
/// the version, and the date must name the same day on every Mac.
struct AppVersionTests {
    private func packaged(
        date: Any? = "2026-09-15",
        version: String = "1.6.2",
        build: String = "10602"
    ) -> AppVersion {
        var info: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ]
        info["AppReleaseDate"] = date
        return AppVersion(infoDictionary: info)
    }

    @Test func packagedBuildShowsVersionBuildAndDate() {
        let metadata = packaged()
        #expect(metadata.displayVersion == "1.6.2 (10602)")
        #expect(metadata.versionLabel == "Version 1.6.2 (10602)")
        #expect(metadata.releaseDateISO == "2026-09-15")
        #expect(
            metadata.releaseDateText(locale: Locale(identifier: "en_US")) == "September 15, 2026")
    }

    @Test func missingDateKeepsVersionAndBuild() {
        let metadata = packaged(date: nil)
        #expect(metadata.displayVersion == "1.6.2 (10602)")
        #expect(metadata.releaseDate == nil)
        #expect(metadata.releaseDateText() == nil)
        #expect(metadata.releaseDateISO == nil)
    }

    @Test func malformedDatesMeanNoDate() {
        for bad: Any in [
            "", "junk", "2026-13-45", "2026-02-30", "2026-9-15",
            "2026-09-15T10:00:00Z", "20260915", 20_260_915,
        ] {
            let metadata = packaged(date: bad)
            #expect(metadata.releaseDate == nil, "\(bad)")
            #expect(metadata.displayVersion == "1.6.2 (10602)", "\(bad)")
        }
    }

    @Test func dateDoesNotShiftWestOfUTC() throws {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(
            packaged().releaseDateText(locale: Locale(identifier: "en_US")) == "September 15, 2026")
        #expect(packaged().releaseDateISO == "2026-09-15")
    }

    @Test func dateFollowsTheLocale() {
        #expect(
            packaged().releaseDateText(locale: Locale(identifier: "pt_BR")) == "15 de setembro de 2026")
    }

    @Test func buildEqualToVersionIsNotRepeated() {
        #expect(packaged(version: "2.0.0", build: "2.0.0").displayVersion == "2.0.0")
    }

    @Test func copyrightComesFromTheBundle() {
        let line = "GPL-3.0. Derived from AltTab, © lwouis and contributors."
        #expect(AppVersion(infoDictionary: ["NSHumanReadableCopyright": line]).copyright == line)
        #expect(packaged().copyright == nil)
    }

    @Test func emptyDictionaryIsAnHonestDevelopmentBuild() {
        let metadata = AppVersion(infoDictionary: [:])
        #expect(metadata.displayVersion == "Development build")
        #expect(metadata.versionLabel == "Development build")
        #expect(metadata.version == nil)
        #expect(metadata.build == nil)
        #expect(metadata.copyright == nil)
        #expect(metadata.releaseDateText() == nil)
    }
}
