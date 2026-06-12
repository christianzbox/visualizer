import Foundation

public struct FrequencyBand: Equatable, Sendable {
    public let name: String
    public let lowFrequency: Float
    public let highFrequency: Float

    public init(name: String, lowFrequency: Float, highFrequency: Float) {
        self.name = name
        self.lowFrequency = lowFrequency
        self.highFrequency = highFrequency
    }
}

public struct BandEnergyResult: Equatable, Sendable {
    public var subBass: Float
    public var bass: Float
    public var lowMids: Float
    public var mids: Float
    public var highMids: Float
    public var treble: Float
}

public enum BandEnergyAnalyzer {
    public static let standardBands = [
        FrequencyBand(name: "Sub Bass", lowFrequency: 20, highFrequency: 60),
        FrequencyBand(name: "Bass", lowFrequency: 60, highFrequency: 250),
        FrequencyBand(name: "Low Mids", lowFrequency: 250, highFrequency: 500),
        FrequencyBand(name: "Mids", lowFrequency: 500, highFrequency: 2_000),
        FrequencyBand(name: "High Mids", lowFrequency: 2_000, highFrequency: 6_000),
        FrequencyBand(name: "Treble", lowFrequency: 6_000, highFrequency: 16_000)
    ]

    public static func energy(
        in band: FrequencyBand,
        magnitudes: [Float],
        sampleRate: Double,
        fftSize: Int
    ) -> Float {
        guard !magnitudes.isEmpty, sampleRate > 0, fftSize > 0 else { return 0 }
        let binWidth = Float(sampleRate) / Float(fftSize)
        let lowBin = max(0, Int(floor(band.lowFrequency / binWidth)))
        let highBin = min(magnitudes.count - 1, Int(ceil(band.highFrequency / binWidth)))
        guard highBin >= lowBin else { return 0 }

        var sum: Float = 0
        for index in lowBin...highBin {
            sum += magnitudes[index]
        }
        let average = sum / Float(highBin - lowBin + 1)
        return normalize(average)
    }

    public static func standardEnergy(
        magnitudes: [Float],
        sampleRate: Double,
        fftSize: Int
    ) -> BandEnergyResult {
        let values = standardBands.map {
            energy(in: $0, magnitudes: magnitudes, sampleRate: sampleRate, fftSize: fftSize)
        }
        return BandEnergyResult(
            subBass: values[0],
            bass: values[1],
            lowMids: values[2],
            mids: values[3],
            highMids: values[4],
            treble: values[5]
        )
    }

    public static func logarithmicBands(
        magnitudes: [Float],
        sampleRate: Double,
        fftSize: Int,
        count: Int,
        minFrequency: Float = 20,
        maxFrequency: Float = 16_000
    ) -> [Float] {
        guard count > 0, !magnitudes.isEmpty else { return [] }
        let minLog = log10(max(minFrequency, 1))
        let maxLog = log10(max(maxFrequency, minFrequency + 1))

        return (0..<count).map { index in
            let startRatio = Float(index) / Float(count)
            let endRatio = Float(index + 1) / Float(count)
            let low = pow(10, minLog + ((maxLog - minLog) * startRatio))
            let high = pow(10, minLog + ((maxLog - minLog) * endRatio))
            return energy(
                in: FrequencyBand(name: "Band \(index)", lowFrequency: low, highFrequency: high),
                magnitudes: magnitudes,
                sampleRate: sampleRate,
                fftSize: fftSize
            )
        }
    }

    private static func normalize(_ value: Float) -> Float {
        min(1, log1p(max(0, value) * 30) / log1p(30))
    }
}
