#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class BandEnergyAnalyzerTests: XCTestCase {
    func testFrequencyToBandMappingWorks() {
        let fftSize = 2_048
        let sampleRate = 48_000.0
        var magnitudes = Array(repeating: Float(0), count: fftSize / 2)
        let bin = Int(100 / (sampleRate / Double(fftSize)))
        magnitudes[bin] = 1

        let bass = BandEnergyAnalyzer.energy(
            in: FrequencyBand(name: "Bass", lowFrequency: 60, highFrequency: 250),
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize
        )
        let treble = BandEnergyAnalyzer.energy(
            in: FrequencyBand(name: "Treble", lowFrequency: 6_000, highFrequency: 16_000),
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize
        )

        XCTAssertGreaterThan(bass, treble)
    }

    func testLogarithmicBandsHaveExpectedCountAndRange() {
        let bands = BandEnergyAnalyzer.logarithmicBands(
            magnitudes: Array(repeating: 0.1, count: 1_024),
            sampleRate: 48_000,
            fftSize: 2_048,
            count: 96
        )

        XCTAssertEqual(bands.count, 96)
        XCTAssertTrue(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}
#endif
