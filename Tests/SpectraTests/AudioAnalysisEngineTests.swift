#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class AudioAnalysisEngineTests: XCTestCase {
    func testSustainedSilenceIsDetectedAfterHoldTime() {
        let engine = AudioAnalysisEngine()
        var output = VisualAudioFrame.silent

        for index in 0..<40 {
            output = engine.process(SpectraTestSupport.frame(
                samples: Array(repeating: 0, count: 512),
                timestamp: Double(index) * 0.02
            ))
        }

        XCTAssertTrue(output.isSilent)
        XCTAssertGreaterThan(output.silenceDuration, 0.25)
    }

    func testBriefGapDoesNotImmediatelyBecomeSilent() {
        let engine = AudioAnalysisEngine()
        _ = engine.process(SpectraTestSupport.frame(
            samples: SpectraTestSupport.sineWave(frequency: 100, count: 512),
            timestamp: 0
        ))

        let output = engine.process(SpectraTestSupport.frame(
            samples: Array(repeating: 0, count: 512),
            timestamp: 0.04
        ))

        XCTAssertFalse(output.isSilent)
    }

    func testStereoInputIsConvertedToMonoForAnalysis() {
        let engine = AudioAnalysisEngine()
        let left = SpectraTestSupport.sineWave(frequency: 110, count: 1_024)
        var interleaved: [Float] = []
        interleaved.reserveCapacity(left.count * 2)
        for sample in left {
            interleaved.append(sample)
            interleaved.append(sample * 0.5)
        }

        let output = engine.process(SpectraTestSupport.frame(
            samples: interleaved,
            sampleRate: 48_000,
            channelCount: 2
        ))

        XCTAssertGreaterThan(output.rms, 0.1)
        XCTAssertGreaterThan(output.bassEnergy, output.trebleEnergy)
    }

    func testMalformedEmptyFrameReturnsSilentFrame() {
        let engine = AudioAnalysisEngine()

        let output = engine.process(AudioBufferFrame(
            timestamp: 0,
            sampleRate: 48_000,
            channelCount: 0,
            frames: 0,
            samples: [],
            sourceId: "empty"
        ))

        XCTAssertTrue(output.isSilent)
        XCTAssertEqual(output.rms, 0)
    }
}
#endif
