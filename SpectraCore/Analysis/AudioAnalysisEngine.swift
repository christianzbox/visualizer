import Accelerate
import Foundation

public final class AudioAnalysisEngine {
    public let fftAnalyzer: FFTAnalyzer
    public let waveformSampleCount: Int

    private let rollingSamples: AudioRingBuffer
    private var volumeEnvelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.24, release: 0.88)
    private var bassEnvelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.18, release: 0.9)
    private var trebleEnvelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.28, release: 0.92)
    private var spectrumSmoother: SpectrumSmoother
    private var spectrumNormalizers: [AdaptiveNormalizer]
    private var bandNormalizers: [AdaptiveNormalizer]
    private var onsetDetector = OnsetDetector()
    private var beatDetector = BeatDetector()
    private var lastTimestamp: TimeInterval?
    private var silenceStartedAt: TimeInterval?

    public init(fftAnalyzer: FFTAnalyzer = FFTAnalyzer(), waveformSampleCount: Int = 256) {
        self.fftAnalyzer = fftAnalyzer
        self.waveformSampleCount = waveformSampleCount
        self.rollingSamples = AudioRingBuffer(capacity: fftAnalyzer.windowSize)
        self.spectrumSmoother = SpectrumSmoother(count: fftAnalyzer.bandCount)
        self.spectrumNormalizers = Array(repeating: AdaptiveNormalizer(ceiling: 0.18), count: fftAnalyzer.bandCount)
        self.bandNormalizers = Array(repeating: AdaptiveNormalizer(ceiling: 0.16), count: 6)
    }

    public func reset() {
        rollingSamples.clear()
        volumeEnvelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.24, release: 0.88)
        bassEnvelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.18, release: 0.9)
        trebleEnvelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.28, release: 0.92)
        spectrumSmoother = SpectrumSmoother(count: fftAnalyzer.bandCount)
        spectrumNormalizers = Array(repeating: AdaptiveNormalizer(ceiling: 0.18), count: fftAnalyzer.bandCount)
        bandNormalizers = Array(repeating: AdaptiveNormalizer(ceiling: 0.16), count: 6)
        onsetDetector = OnsetDetector()
        beatDetector = BeatDetector()
        lastTimestamp = nil
        silenceStartedAt = nil
    }

    public func process(_ frame: AudioBufferFrame) -> VisualAudioFrame {
        let mono = makeMonoSamples(frame)
        guard !mono.isEmpty else { return .silent }

        let deltaTime = lastTimestamp.map { max(1.0 / 240.0, min(0.1, frame.timestamp - $0)) } ?? (Double(mono.count) / frame.sampleRate)
        rollingSamples.append(mono)

        let rms = Self.rms(mono)
        let peak = Self.peak(mono)
        let fft = fftAnalyzer.analyze(samples: rollingSamples.latest(fftAnalyzer.windowSize), sampleRate: frame.sampleRate)
        let normalizedSpectrum = normalizeSpectrum(fft.spectrumBands)
        let smoothedSpectrum = spectrumSmoother.process(normalizedSpectrum, deltaTime: deltaTime)
        let normalizedBands = normalizeBands(fft.bandEnergies)
        let onset = onsetDetector.process(spectrum: normalizedSpectrum)
        let combinedEnergy = min(1, (normalizedBands.bass * 0.48) + (normalizedBands.lowMids * 0.18) + (rms * 1.45))
        let beat = beatDetector.process(
            energy: combinedEnergy,
            bassEnergy: normalizedBands.bass,
            onsetStrength: onset,
            timestamp: frame.timestamp
        )

        let smoothedVolume = volumeEnvelope.process(min(1, rms * 2.4), deltaTime: deltaTime)
        let smoothedBass = bassEnvelope.process(normalizedBands.bass, deltaTime: deltaTime)
        let smoothedTreble = trebleEnvelope.process(normalizedBands.treble, deltaTime: deltaTime)
        let belowSilenceThreshold = rms < 0.0015 && peak < 0.006 && smoothedVolume < 0.018

        if belowSilenceThreshold {
            if silenceStartedAt == nil {
                silenceStartedAt = frame.timestamp
            }
        } else {
            silenceStartedAt = nil
        }
        let silenceDuration = frame.timestamp - (silenceStartedAt ?? frame.timestamp)
        let silent = belowSilenceThreshold && silenceDuration >= 0.28

        lastTimestamp = frame.timestamp

        return VisualAudioFrame(
            timestamp: frame.timestamp,
            rms: rms,
            peak: peak,
            subBassEnergy: normalizedBands.subBass,
            bassEnergy: normalizedBands.bass,
            lowMidEnergy: normalizedBands.lowMids,
            midEnergy: normalizedBands.mids,
            highMidEnergy: normalizedBands.highMids,
            trebleEnergy: normalizedBands.treble,
            spectrumBands: smoothedSpectrum,
            waveform: Self.downsample(mono, count: waveformSampleCount),
            beatPulse: beat,
            onsetStrength: onset,
            smoothedVolume: smoothedVolume,
            smoothedBass: smoothedBass,
            smoothedTreble: smoothedTreble,
            estimatedTempo: nil,
            isSilent: silent,
            silenceDuration: belowSilenceThreshold ? silenceDuration : 0
        )
    }

    private func makeMonoSamples(_ frame: AudioBufferFrame) -> [Float] {
        guard frame.channelCount > 0, !frame.samples.isEmpty else { return [] }
        if frame.channelCount == 1 {
            return Array(frame.samples.prefix(frame.frames))
        }

        var mono = Array(repeating: Float(0), count: frame.frames)
        for frameIndex in 0..<frame.frames {
            var sum: Float = 0
            for channel in 0..<frame.channelCount {
                let sampleIndex = (frameIndex * frame.channelCount) + channel
                if sampleIndex < frame.samples.count {
                    sum += frame.samples[sampleIndex]
                }
            }
            mono[frameIndex] = sum / Float(frame.channelCount)
        }
        return mono
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var output: Float = 0
        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            vDSP_rmsqv(base, 1, &output, vDSP_Length(samples.count))
        }
        return output
    }

    private static func peak(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var output: Float = 0
        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            vDSP_maxmgv(base, 1, &output, vDSP_Length(samples.count))
        }
        return output
    }

    private static func downsample(_ samples: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        if samples.count == count { return samples }

        var output = Array(repeating: Float(0), count: count)
        let stride = Float(samples.count) / Float(count)
        for index in 0..<count {
            let start = Int(Float(index) * stride)
            let end = min(samples.count, max(start + 1, Int(Float(index + 1) * stride)))
            var sum: Float = 0
            for sampleIndex in start..<end {
                sum += samples[sampleIndex]
            }
            output[index] = max(-1, min(1, sum / Float(end - start)))
        }
        return output
    }

    private func normalizeSpectrum(_ spectrum: [Float]) -> [Float] {
        guard !spectrum.isEmpty else { return [] }
        if spectrumNormalizers.count != spectrum.count {
            spectrumNormalizers = Array(repeating: AdaptiveNormalizer(ceiling: 0.18), count: spectrum.count)
        }
        return spectrum.indices.map { index in
            let shaped = pow(max(0, spectrum[index]), 0.82)
            return spectrumNormalizers[index].normalize(shaped)
        }
    }

    private func normalizeBands(_ bands: BandEnergyResult) -> BandEnergyResult {
        if bandNormalizers.count != 6 {
            bandNormalizers = Array(repeating: AdaptiveNormalizer(ceiling: 0.16), count: 6)
        }
        return BandEnergyResult(
            subBass: bandNormalizers[0].normalize(pow(max(0, bands.subBass), 0.86)),
            bass: bandNormalizers[1].normalize(pow(max(0, bands.bass), 0.82)),
            lowMids: bandNormalizers[2].normalize(pow(max(0, bands.lowMids), 0.88)),
            mids: bandNormalizers[3].normalize(pow(max(0, bands.mids), 0.92)),
            highMids: bandNormalizers[4].normalize(pow(max(0, bands.highMids), 0.94)),
            treble: bandNormalizers[5].normalize(pow(max(0, bands.treble), 0.82))
        )
    }
}
