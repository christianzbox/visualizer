#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class BeatDetectorTests: XCTestCase {
    func testPulseSequenceProducesBeatPulse() {
        var detector = BeatDetector(historySize: 12, thresholdMultiplier: 1.3, minimumBeatInterval: 0.1)
        var pulses: [Float] = []

        for index in 0..<40 {
            let isPulse = index == 10 || index == 24
            pulses.append(detector.process(
                energy: isPulse ? 0.85 : 0.08,
                bassEnergy: isPulse ? 0.9 : 0.1,
                onsetStrength: isPulse ? 0.5 : 0.02,
                timestamp: Double(index) * 0.05
            ))
        }

        XCTAssertGreaterThan(pulses.max() ?? 0, 0.8)
    }

    func testSteadyToneDoesNotConstantlyTriggerBeats() {
        var detector = BeatDetector(historySize: 12, thresholdMultiplier: 1.3, minimumBeatInterval: 0.1)
        var triggered = 0

        for index in 0..<40 {
            let pulse = detector.process(
                energy: 0.34,
                bassEnergy: 0.34,
                onsetStrength: 0.03,
                timestamp: Double(index) * 0.05
            )
            if pulse > 0.9 { triggered += 1 }
        }

        XCTAssertEqual(triggered, 0)
    }

    func testSilenceDoesNotTriggerBeats() {
        var detector = BeatDetector()
        let pulses = (0..<20).map { index in
            detector.process(
                energy: 0,
                bassEnergy: 0,
                onsetStrength: 0,
                timestamp: Double(index) * 0.05
            )
        }

        XCTAssertEqual(pulses.max(), 0)
    }
}
#endif
