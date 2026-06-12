import Accelerate
import Foundation

public struct AudioLevelSnapshot: Equatable, Sendable {
    public var rms: Float
    public var peak: Float
    public var decibels: Float

    public static let zero = AudioLevelSnapshot(rms: 0, peak: 0, decibels: -96)
}

public enum AudioLevelMeter {
    public static func measure(_ frame: AudioBufferFrame) -> AudioLevelSnapshot {
        guard !frame.samples.isEmpty else { return .zero }

        var rms: Float = 0
        var peak: Float = 0
        frame.samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            vDSP_rmsqv(base, 1, &rms, vDSP_Length(pointer.count))
            vDSP_maxmgv(base, 1, &peak, vDSP_Length(pointer.count))
        }

        let db = rms > 0 ? 20 * log10(max(rms, 0.000_001)) : -96
        return AudioLevelSnapshot(rms: rms, peak: peak, decibels: max(-96, db))
    }
}
