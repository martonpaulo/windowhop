import Foundation
import Testing

@testable import WindowHopKit

/// Acquisition state is per window for the session, so list refreshes and
/// reorders cannot erase or move a failure or a permission block.
struct PreviewAvailabilityTests {
    @Test func untouchedWindowIsLoading() {
        let availability = PreviewAvailability<String>()
        #expect(availability.presentation(for: "a", hasImage: false) == .loading)
    }

    @Test func precedenceIsImageThenPermissionThenFailureThenLoading() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        #expect(availability.presentation(for: "a", hasImage: false) == .captureUnavailable)
        #expect(availability.presentation(for: "b", hasImage: false) == .loading)

        availability.permissionChanged(authorized: false)
        #expect(availability.presentation(for: "a", hasImage: false) == .permissionUnavailable)
        #expect(availability.presentation(for: "b", hasImage: false) == .permissionUnavailable)

        // a cached image always wins over any failure state
        #expect(availability.presentation(for: "a", hasImage: true) == .loaded)
    }

    @Test func regrantingPermissionRevealsTheRecordedFailureAgain() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.permissionChanged(authorized: false)
        availability.permissionChanged(authorized: true)
        #expect(availability.presentation(for: "a", hasImage: false) == .captureUnavailable)
        #expect(availability.presentation(for: "b", hasImage: false) == .loading)
    }

    @Test func failureSurvivesRetainingItsWindow() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.retain(["b", "a"])
        #expect(availability.presentation(for: "a", hasImage: false) == .captureUnavailable)
    }

    @Test func prunedWindowReturnsAsLoading() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.retain(["b"])
        availability.retain(["a", "b"])
        #expect(availability.presentation(for: "a", hasImage: false) == .loading)
    }

    @Test func successClearsAFailure() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.captureSucceeded("a")
        #expect(availability.presentation(for: "a", hasImage: false) == .loading)
    }

    @Test func beginSessionResetsFailuresAndPermission() {
        var availability = PreviewAvailability<String>()
        availability.captureFailed("a")
        availability.permissionChanged(authorized: false)
        availability.beginSession()
        #expect(!availability.permissionBlocked)
        #expect(availability.presentation(for: "a", hasImage: false) == .loading)
    }
}
