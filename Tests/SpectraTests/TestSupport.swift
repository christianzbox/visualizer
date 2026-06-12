#if canImport(XCTest)
import Foundation
@testable import SpectraCore

enum SpectraTestSupport {
    static func sineWave(
        frequency: Double,
        sampleRate: Double = 48_000,
        count: Int,
        amplitude: Double = 0.8
    ) -> [Float] {
        (0..<count).map { index in
            Float(sin((Double(index) / sampleRate) * frequency * Double.pi * 2) * amplitude)
        }
    }

    static func frame(
        samples: [Float],
        timestamp: TimeInterval = 0,
        sampleRate: Double = 48_000,
        channelCount: Int = 1,
        sourceId: String = "test"
    ) -> AudioBufferFrame {
        AudioBufferFrame(
            timestamp: timestamp,
            sampleRate: sampleRate,
            channelCount: channelCount,
            frames: max(0, samples.count / max(1, channelCount)),
            samples: samples,
            sourceId: sourceId
        )
    }
}
#endif
