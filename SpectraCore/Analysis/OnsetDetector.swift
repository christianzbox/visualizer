import Foundation

public struct OnsetDetector: Sendable {
    private var previousSpectrum: [Float] = []
    private var smoother = ExponentialSmoother(initialValue: 0, smoothing: 0.72)

    public init() {}

    public mutating func process(spectrum: [Float]) -> Float {
        guard !spectrum.isEmpty else { return 0 }
        if previousSpectrum.count != spectrum.count {
            previousSpectrum = spectrum
            return 0
        }

        var flux: Float = 0
        for index in spectrum.indices {
            let previous = max(previousSpectrum[index], 0.0001)
            flux += max(0, (spectrum[index] - previousSpectrum[index]) / previous)
        }
        previousSpectrum = spectrum
        let normalized = min(1, flux / Float(spectrum.count) * 0.55)
        return smoother.process(normalized)
    }
}
