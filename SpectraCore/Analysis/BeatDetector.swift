import Foundation

public struct BeatDetector: Sendable {
    private var energyHistory: [Float]
    private var index = 0
    private var filled = 0
    private var lastBeatTime: TimeInterval = -1
    private var lastProcessTime: TimeInterval?
    private var pulse: Float = 0

    public var thresholdMultiplier: Float
    public var minimumBeatInterval: TimeInterval

    public init(historySize: Int = 48, thresholdMultiplier: Float = 1.42, minimumBeatInterval: TimeInterval = 0.18) {
        self.energyHistory = Array(repeating: 0, count: max(4, historySize))
        self.thresholdMultiplier = thresholdMultiplier
        self.minimumBeatInterval = minimumBeatInterval
    }

    public mutating func process(
        energy: Float,
        bassEnergy: Float,
        onsetStrength: Float,
        timestamp: TimeInterval
    ) -> Float {
        let history = energyHistory.prefix(filled)
        let averageEnergy = filled > 0 ? history.reduce(0, +) / Float(filled) : 0
        let variance = filled > 1 ? history.reduce(Float(0)) { partial, sample in
            let delta = sample - averageEnergy
            return partial + (delta * delta)
        } / Float(filled - 1) : 0
        let deviation = sqrt(max(0, variance))
        let dynamicThreshold = max(0.035, averageEnergy * thresholdMultiplier + deviation * 0.55)
        let transient = energy > dynamicThreshold
        let bassTransient = bassEnergy > max(0.08, averageEnergy * 0.8)
        let onsetTransient = onsetStrength > max(0.08, averageEnergy * 0.22)
        let canTrigger = lastBeatTime < 0 || timestamp - lastBeatTime >= minimumBeatInterval

        if transient && bassTransient && onsetTransient && canTrigger {
            pulse = 1
            lastBeatTime = timestamp
        } else {
            let delta = lastProcessTime.map { max(1.0 / 240.0, min(0.1, timestamp - $0)) } ?? (1.0 / 60.0)
            pulse = max(0, pulse - Float(delta) * 4.2)
        }

        energyHistory[index] = energy
        index = (index + 1) % energyHistory.count
        filled = min(filled + 1, energyHistory.count)
        lastProcessTime = timestamp
        return pulse
    }
}
