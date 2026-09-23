import Foundation
import ScreenCaptureKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

/// A capture error keeps its meaning (#91): only a broken connection or a
/// system hiccup may be retried, a declined grant is a permission state, and
/// anything else, including an unknown error, is stable.
struct PreviewCaptureFailureTests {
    @MainActor
    private func failure(_ code: SCStreamError.Code) -> PreviewFailure {
        PreviewProvider.failure(for: SCStreamError(code))
    }

    @MainActor
    @Test func connectionAndSystemErrorsAreTransient() {
        let transient: [SCStreamError.Code] = [
            .internalError, .failedApplicationConnectionInterrupted,
            .failedApplicationConnectionInvalid, .noWindowList, .systemStoppedStream,
        ]
        for code in transient {
            #expect(failure(code) == .captureFailed(transient: true), "\(code)")
        }
    }

    @MainActor
    @Test func aDeclinedGrantIsAPermissionStateNotARetry() {
        #expect(failure(.userDeclined) == .permissionDenied)
    }

    @MainActor
    @Test func targetAndConfigurationErrorsAreStable() {
        let stable: [SCStreamError.Code] = [
            .missingEntitlements, .noCaptureSource, .invalidParameter,
            .failedNoMatchingApplicationContext, .failedToStart,
        ]
        for code in stable {
            #expect(failure(code) == .captureFailed(transient: false), "\(code)")
        }
    }

    /// The framework reports errors as NSError in its own domain.
    @MainActor
    @Test func aBridgedNSErrorIsClassifiedByItsCode() {
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.internalError.rawValue)
        #expect(PreviewProvider.failure(for: error) == .captureFailed(transient: true))
    }

    @MainActor
    @Test func anUnknownErrorIsStable() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 1)
        #expect(PreviewProvider.failure(for: error) == .captureFailed(transient: false))
    }
}
