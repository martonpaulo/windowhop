import Foundation
import Testing

@testable import WindowHopCore

struct ScreenRecordingPermissionTests {
    @Test func authorizedDeniedRestrictedAndNotDeterminedStates() {
        #expect(
            ScreenRecordingPermission.classify(
                preflightGranted: true, hasRequested: false, isRestricted: false) == .authorized)
        #expect(
            ScreenRecordingPermission.classify(
                preflightGranted: false, hasRequested: true, isRestricted: false) == .denied)
        #expect(
            ScreenRecordingPermission.classify(
                preflightGranted: false, hasRequested: false, isRestricted: true) == .restricted)
        #expect(
            ScreenRecordingPermission.classify(
                preflightGranted: false, hasRequested: false, isRestricted: false) == .notDetermined)
    }

    @Test func permissionRevocationChangesAuthorizedToBlocked() {
        let before = ScreenRecordingPermission.classify(
            preflightGranted: true, hasRequested: true, isRestricted: false)
        let after = ScreenRecordingPermission.classify(
            preflightGranted: false, hasRequested: true, isRestricted: false)

        #expect(before.isAuthorized)
        #expect(after.requiresPermission)
        #expect(after == .denied)
    }
}
