#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class SmoothingTests: XCTestCase {
    func testExponentialSmoothingBehavesAsExpected() {
        var smoother = ExponentialSmoother(initialValue: 0, smoothing: 0.5)

        XCTAssertEqual(smoother.process(1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(smoother.process(1), 0.75, accuracy: 0.0001)
    }

    func testAttackReleaseEnvelopeRespondsQuicklyToAttackAndSlowerToRelease() {
        var envelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.2, release: 0.9)

        let attack = envelope.process(1)
        let release = envelope.process(0)

        XCTAssertGreaterThan(attack, 0.7)
        XCTAssertGreaterThan(release, 0.6)
        XCTAssertLessThan(release, attack)
    }
}
#endif
