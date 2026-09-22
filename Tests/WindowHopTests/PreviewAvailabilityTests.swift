import XCTest
@testable import WindowHopCore

/// Acquisition state is per window for the session, so list refreshes and
/// reorders cannot erase or move a failure or a permission block.
final class PreviewAvailabilityTests: XCTestCase {
    func testUntouchedWindowIsLoading() {
        let availability = PreviewAvailability<String>()
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .loading)
    }

    func testPrecedenceIsImageThenPermissionThenFailureThenLoading() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .captureUnavailable)
        XCTAssertEqual(availability.presentation(for: "b", hasImage: false), .loading)

        availability.permissionChanged(authorized: false)
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .permissionUnavailable)
        XCTAssertEqual(availability.presentation(for: "b", hasImage: false), .permissionUnavailable)

        // a cached image always wins over any failure state
        XCTAssertEqual(availability.presentation(for: "a", hasImage: true), .loaded)
    }

    func testRegrantingPermissionRevealsTheRecordedFailureAgain() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.permissionChanged(authorized: false)
        availability.permissionChanged(authorized: true)
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .captureUnavailable)
        XCTAssertEqual(availability.presentation(for: "b", hasImage: false), .loading)
    }

    func testFailureSurvivesRetainingItsWindow() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.retain(["b", "a"])
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .captureUnavailable)
    }

    func testPrunedWindowReturnsAsLoading() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.retain(["b"])
        availability.retain(["a", "b"])
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .loading)
    }

    func testSuccessClearsAFailure() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.captureSucceeded("a")
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .loading)
    }

    func testBeginSessionResetsFailuresAndPermission() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.permissionChanged(authorized: false)
        availability.beginSession()
        XCTAssertFalse(availability.permissionBlocked)
        XCTAssertEqual(availability.presentation(for: "a", hasImage: false), .loading)
    }
}
