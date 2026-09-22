import Foundation
import XCTest
@testable import WindowHopCore

/// About, Updates and support reports show the version, build and release
/// date through `AppVersion`. A missing or bad release date must never hide
/// the version, and the date must name the same day on every Mac.
final class AppVersionTests: XCTestCase {
    private func packaged(date: Any? = "2026-09-15",
                          version: String = "1.6.2",
                          build: String = "10602") -> AppVersion {
        var info: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ]
        info["AppReleaseDate"] = date
        return AppVersion(infoDictionary: info)
    }

    func testPackagedBuildShowsVersionBuildAndDate() {
        let metadata = packaged()
        XCTAssertEqual(metadata.displayVersion, "1.6.2 (10602)")
        XCTAssertEqual(metadata.versionLabel, "Version 1.6.2 (10602)")
        XCTAssertEqual(metadata.releaseDateISO, "2026-09-15")
        XCTAssertEqual(metadata.releaseDateText(locale: Locale(identifier: "en_US")),
                       "September 15, 2026")
    }

    func testMissingDateKeepsVersionAndBuild() {
        let metadata = packaged(date: nil)
        XCTAssertEqual(metadata.displayVersion, "1.6.2 (10602)")
        XCTAssertNil(metadata.releaseDate)
        XCTAssertNil(metadata.releaseDateText())
        XCTAssertNil(metadata.releaseDateISO)
    }

    func testMalformedDatesMeanNoDate() {
        for bad: Any in ["", "junk", "2026-13-45", "2026-02-30", "2026-9-15",
                         "2026-09-15T10:00:00Z", "20260915", 20_260_915] {
            let metadata = packaged(date: bad)
            XCTAssertNil(metadata.releaseDate, "\(bad)")
            XCTAssertEqual(metadata.displayVersion, "1.6.2 (10602)", "\(bad)")
        }
    }

    func testDateDoesNotShiftWestOfUTC() {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(packaged().releaseDateText(locale: Locale(identifier: "en_US")),
                       "September 15, 2026")
        XCTAssertEqual(packaged().releaseDateISO, "2026-09-15")
    }

    func testDateFollowsTheLocale() {
        XCTAssertEqual(packaged().releaseDateText(locale: Locale(identifier: "pt_BR")),
                       "15 de setembro de 2026")
    }

    func testBuildEqualToVersionIsNotRepeated() {
        XCTAssertEqual(packaged(version: "2.0.0", build: "2.0.0").displayVersion, "2.0.0")
    }

    func testEmptyDictionaryIsAnHonestDevelopmentBuild() {
        let metadata = AppVersion(infoDictionary: [:])
        XCTAssertEqual(metadata.displayVersion, "Development build")
        XCTAssertEqual(metadata.versionLabel, "Development build")
        XCTAssertNil(metadata.version)
        XCTAssertNil(metadata.build)
        XCTAssertNil(metadata.releaseDateText())
    }
}
