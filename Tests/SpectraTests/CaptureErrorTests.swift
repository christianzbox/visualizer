#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class CaptureErrorTests: XCTestCase {
    func testPermissionDeniedHasActionableRecoverySuggestion() {
        let error = AudioCaptureError.permissionDenied

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.recoverySuggestion?.contains("Test Signal Mode") == true)
        XCTAssertTrue(error.failureReason?.contains("Screen") == true)
    }

    func testUnsupportedOSMentionsTestSignalFallback() {
        let error = AudioCaptureError.unsupportedOS("Unsupported")

        XCTAssertTrue(error.recoverySuggestion?.contains("Test Signal Mode") == true)
    }
}
#endif
