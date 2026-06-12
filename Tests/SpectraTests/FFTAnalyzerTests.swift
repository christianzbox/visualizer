#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class FFTAnalyzerTests: XCTestCase {
    func testSineWaveProducesExpectedBandEnergy() {
        let analyzer = FFTAnalyzer(windowSize: 2_048, bandCount: 64)
        let samples = sineWave(frequency: 440, sampleRate: 48_000, count: 2_048)

        let result = analyzer.analyze(samples: samples, sampleRate: 48_000)

        XCTAssertGreaterThan(result.bandEnergies.lowMids, result.bandEnergies.subBass)
        XCTAssertGreaterThan(result.bandEnergies.lowMids, result.bandEnergies.treble)
        XCTAssertEqual(result.spectrumBands.count, 64)
    }

    func testSilenceProducesNearZeroOutput() {
        let analyzer = FFTAnalyzer(windowSize: 2_048, bandCount: 64)
        let result = analyzer.analyze(samples: Array(repeating: 0, count: 2_048), sampleRate: 48_000)

        XCTAssertLessThan(result.magnitudes.reduce(0, +), 0.0001)
        XCTAssertLessThan(result.bandEnergies.bass, 0.0001)
    }

    func testBassToneIncreasesBassEnergy() {
        let analyzer = FFTAnalyzer(windowSize: 2_048, bandCount: 64)
        let samples = sineWave(frequency: 95, sampleRate: 48_000, count: 2_048)

        let result = analyzer.analyze(samples: samples, sampleRate: 48_000)

        XCTAssertGreaterThan(result.bandEnergies.bass, result.bandEnergies.mids)
        XCTAssertGreaterThan(result.bandEnergies.bass, result.bandEnergies.treble)
    }

    private func sineWave(frequency: Double, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { index in
            Float(sin((Double(index) / sampleRate) * frequency * Double.pi * 2) * 0.8)
        }
    }
}
#endif
