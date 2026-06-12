import Foundation

public struct ExponentialSmoother: Sendable {
    public var value: Float
    public var smoothing: Float

    public init(initialValue: Float = 0, smoothing: Float) {
        self.value = initialValue
        self.smoothing = min(max(smoothing, 0), 0.999)
    }

    public mutating func process(_ input: Float) -> Float {
        value = (smoothing * value) + ((1 - smoothing) * input)
        return value
    }
}

public struct AttackReleaseEnvelope: Sendable {
    public var value: Float
    public var attack: Float
    public var release: Float

    public init(initialValue: Float = 0, attack: Float = 0.35, release: Float = 0.92) {
        self.value = initialValue
        self.attack = attack
        self.release = release
    }

    public mutating func process(_ input: Float) -> Float {
        let coefficient = input > value ? attack : release
        value = (coefficient * value) + ((1 - coefficient) * input)
        return value
    }

    public mutating func process(_ input: Float, deltaTime: TimeInterval) -> Float {
        let baseCoefficient = input > value ? attack : release
        let normalizedDelta = max(0.0, min(0.1, deltaTime)) * 60.0
        let coefficient = pow(baseCoefficient, Float(normalizedDelta))
        value = (coefficient * value) + ((1 - coefficient) * input)
        return value
    }
}

public struct PeakHoldDecay: Sendable {
    public private(set) var value: Float = 0
    public var decayPerSecond: Float

    public init(decayPerSecond: Float = 1.8) {
        self.decayPerSecond = decayPerSecond
    }

    public mutating func process(_ input: Float, deltaTime: TimeInterval) -> Float {
        if input >= value {
            value = input
        } else {
            value = max(0, value - (decayPerSecond * Float(deltaTime)))
        }
        return value
    }
}

public struct RollingNormalizer: Sendable {
    private var history: [Float]
    private var index: Int = 0
    private var filled = 0

    public init(capacity: Int = 120) {
        self.history = Array(repeating: 0, count: max(1, capacity))
    }

    public mutating func normalize(_ value: Float) -> Float {
        history[index] = max(value, 0.000_001)
        index = (index + 1) % history.count
        filled = min(filled + 1, history.count)
        let active = history.prefix(filled)
        let floor = active.min() ?? 0
        let ceiling = active.max() ?? 1
        guard ceiling > floor else { return 0 }
        return min(max((value - floor) / (ceiling - floor), 0), 1)
    }
}

public struct AdaptiveNormalizer: Sendable {
    private var floor: Float
    private var ceiling: Float
    private let rise: Float
    private let fall: Float

    public init(floor: Float = 0, ceiling: Float = 0.08, rise: Float = 0.18, fall: Float = 0.995) {
        self.floor = floor
        self.ceiling = max(ceiling, floor + 0.001)
        self.rise = min(max(rise, 0), 1)
        self.fall = min(max(fall, 0), 0.9999)
    }

    public mutating func normalize(_ input: Float) -> Float {
        let value = max(0, input)
        if value > ceiling {
            ceiling = (ceiling * (1 - rise)) + (value * rise)
        } else {
            ceiling = max(value, ceiling * fall)
        }

        if value < floor {
            floor = (floor * 0.96) + (value * 0.04)
        } else {
            floor = min(value * 0.35, (floor * 0.995) + (value * 0.005))
        }

        let range = max(0.0001, ceiling - floor)
        return min(1, max(0, (value - floor) / range))
    }
}

public struct SpectrumSmoother: Sendable {
    private var values: [Float]
    private let attack: Float
    private let release: Float

    public init(count: Int, attack: Float = 0.34, release: Float = 0.82) {
        self.values = Array(repeating: 0, count: max(0, count))
        self.attack = attack
        self.release = release
    }

    public mutating func process(_ input: [Float], deltaTime: TimeInterval) -> [Float] {
        if values.count != input.count {
            values = Array(repeating: 0, count: input.count)
        }
        guard !input.isEmpty else { return [] }

        let normalizedDelta = max(0.0, min(0.1, deltaTime)) * 60.0
        let attackCoefficient = pow(attack, Float(normalizedDelta))
        let releaseCoefficient = pow(release, Float(normalizedDelta))

        for index in input.indices {
            let coefficient = input[index] > values[index] ? attackCoefficient : releaseCoefficient
            values[index] = (coefficient * values[index]) + ((1 - coefficient) * input[index])
        }
        return values
    }
}
