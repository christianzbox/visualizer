import Accelerate
import Foundation

public struct FFTAnalysisResult: Equatable, Sendable {
    public var magnitudes: [Float]
    public var spectrumBands: [Float]
    public var bandEnergies: BandEnergyResult
}

public final class FFTAnalyzer {
    public let windowSize: Int
    public let bandCount: Int

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]

    public init(windowSize: Int = 2_048, bandCount: Int = 96) {
        precondition(windowSize > 0 && (windowSize & (windowSize - 1)) == 0, "FFT windowSize must be a power of two")
        self.windowSize = windowSize
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Float(windowSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = (0..<windowSize).map { index in
            0.5 - 0.5 * cos((2 * Float.pi * Float(index)) / Float(windowSize - 1))
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    public func analyze(samples: [Float], sampleRate: Double) -> FFTAnalysisResult {
        let prepared = prepareWindow(samples)
        let halfCount = windowSize / 2
        var windowed = Array(repeating: Float(0), count: windowSize)
        var magnitudes = Array(repeating: Float(0), count: halfCount)

        prepared.withUnsafeBufferPointer { inputPointer in
            window.withUnsafeBufferPointer { windowPointer in
                guard let input = inputPointer.baseAddress, let win = windowPointer.baseAddress else { return }
                vDSP_vmul(input, 1, win, 1, &windowed, 1, vDSP_Length(windowSize))
            }
        }

        var real = Array(repeating: Float(0), count: halfCount)
        var imaginary = Array(repeating: Float(0), count: halfCount)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                guard let realBase = realPointer.baseAddress,
                      let imaginaryBase = imaginaryPointer.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)

                windowed.withUnsafeBufferPointer { windowedPointer in
                    guard let base = windowedPointer.baseAddress else { return }
                    base.withMemoryRebound(to: DSPComplex.self, capacity: halfCount) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(halfCount))
                    }
                }

                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfCount))
            }
        }

        var scale = Float(1.0 / Float(windowSize))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(magnitudes.count))

        let energies = BandEnergyAnalyzer.standardEnergy(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: windowSize
        )
        let bands = BandEnergyAnalyzer.logarithmicBands(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: windowSize,
            count: bandCount
        )

        return FFTAnalysisResult(
            magnitudes: magnitudes,
            spectrumBands: bands,
            bandEnergies: energies
        )
    }

    private func prepareWindow(_ samples: [Float]) -> [Float] {
        if samples.count == windowSize {
            return samples
        }
        if samples.count > windowSize {
            return Array(samples.suffix(windowSize))
        }
        return Array(repeating: 0, count: windowSize - samples.count) + samples
    }
}
