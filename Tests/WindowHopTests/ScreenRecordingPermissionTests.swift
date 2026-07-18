import XCTest
@testable import WindowHopCore

final class ScreenRecordingPermissionTests: XCTestCase {
    func testAuthorizedDeniedRestrictedAndNotDeterminedStates() {
        XCTAssertEqual(ScreenRecordingPermission.classify(
            preflightGranted: true, hasRequested: false, isRestricted: false), .authorized)
        XCTAssertEqual(ScreenRecordingPermission.classify(
            preflightGranted: false, hasRequested: true, isRestricted: false), .denied)
        XCTAssertEqual(ScreenRecordingPermission.classify(
            preflightGranted: false, hasRequested: false, isRestricted: true), .restricted)
        XCTAssertEqual(ScreenRecordingPermission.classify(
            preflightGranted: false, hasRequested: false, isRestricted: false), .notDetermined)
    }

    func testPermissionRevocationChangesAuthorizedToBlocked() {
        let before = ScreenRecordingPermission.classify(
            preflightGranted: true, hasRequested: true, isRestricted: false)
        let after = ScreenRecordingPermission.classify(
            preflightGranted: false, hasRequested: true, isRestricted: false)

        XCTAssertTrue(before.isAuthorized)
        XCTAssertTrue(after.requiresPermission)
        XCTAssertEqual(after, .denied)
    }
}
