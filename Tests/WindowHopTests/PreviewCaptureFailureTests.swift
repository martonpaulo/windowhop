import Foundation
import ScreenCaptureKit
import XCTest

@testable import WindowHopCore
@testable import WindowHopKit

/// A capture error keeps its meaning (#91): only a broken connection or a
/// system hiccup may be retried, a declined grant is a permission state, and
/// anything else, including an unknown error, is stable.
final class PreviewCaptureFailureTests: XCTestCase {
    @MainActor
    private func failure(_ code: SCStreamError.Code) -> PreviewFailure {
        PreviewProvider.failure(for: SCStreamError(code))
    }

    @MainActor
    func testConnectionAndSystemErrorsAreTransient() {
        let transient: [SCStreamError.Code] = [
            .internalError, .failedApplicationConnectionInterrupted,
            .failedApplicationConnectionInvalid, .noWindowList, .systemStoppedStream,
        ]
        for code in transient {
            XCTAssertEqual(failure(code), .captureFailed(transient: true), "\(code)")
        }
    }

    @MainActor
    func testADeclinedGrantIsAPermissionStateNotARetry() {
        XCTAssertEqual(failure(.userDeclined), .permissionDenied)
    }

    @MainActor
    func testTargetAndConfigurationErrorsAreStable() {
        let stable: [SCStreamError.Code] = [
            .missingEntitlements, .noCaptureSource, .invalidParameter,
            .failedNoMatchingApplicationContext, .failedToStart,
        ]
        for code in stable {
            XCTAssertEqual(failure(code), .captureFailed(transient: false), "\(code)")
        }
    }

    /// The framework reports errors as NSError in its own domain.
    @MainActor
    func testABridgedNSErrorIsClassifiedByItsCode() {
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.internalError.rawValue)
        XCTAssertEqual(PreviewProvider.failure(for: error), .captureFailed(transient: true))
    }

    @MainActor
    func testAnUnknownErrorIsStable() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 1)
        XCTAssertEqual(PreviewProvider.failure(for: error), .captureFailed(transient: false))
    }
}
