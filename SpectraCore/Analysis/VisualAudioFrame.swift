import Foundation

public struct VisualAudioFrame: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var rms: Float
    public var peak: Float
    public var subBassEnergy: Float
    public var bassEnergy: Float
    public var lowMidEnergy: Float
    public var midEnergy: Float
    public var highMidEnergy: Float
    public var trebleEnergy: Float
    public var spectrumBands: [Float]
    public var waveform: [Float]
    public var beatPulse: Float
    public var onsetStrength: Float
    public var smoothedVolume: Float
    public var smoothedBass: Float
    public var smoothedTreble: Float
    public var estimatedTempo: Float?
    public var isSilent: Bool
    public var silenceDuration: TimeInterval

    public init(
        timestamp: TimeInterval,
        rms: Float,
        peak: Float,
        subBassEnergy: Float,
        bassEnergy: Float,
        lowMidEnergy: Float,
        midEnergy: Float,
        highMidEnergy: Float,
        trebleEnergy: Float,
        spectrumBands: [Float],
        waveform: [Float],
        beatPulse: Float,
        onsetStrength: Float,
        smoothedVolume: Float,
        smoothedBass: Float,
        smoothedTreble: Float,
        estimatedTempo: Float?,
        isSilent: Bool,
        silenceDuration: TimeInterval
    ) {
        self.timestamp = timestamp
        self.rms = rms
        self.peak = peak
        self.subBassEnergy = subBassEnergy
        self.bassEnergy = bassEnergy
        self.lowMidEnergy = lowMidEnergy
        self.midEnergy = midEnergy
        self.highMidEnergy = highMidEnergy
        self.trebleEnergy = trebleEnergy
        self.spectrumBands = spectrumBands
        self.waveform = waveform
        self.beatPulse = beatPulse
        self.onsetStrength = onsetStrength
        self.smoothedVolume = smoothedVolume
        self.smoothedBass = smoothedBass
        self.smoothedTreble = smoothedTreble
        self.estimatedTempo = estimatedTempo
        self.isSilent = isSilent
        self.silenceDuration = silenceDuration
    }

    public static let silent = VisualAudioFrame(
        timestamp: 0,
        rms: 0,
        peak: 0,
        subBassEnergy: 0,
        bassEnergy: 0,
        lowMidEnergy: 0,
        midEnergy: 0,
        highMidEnergy: 0,
        trebleEnergy: 0,
        spectrumBands: Array(repeating: 0, count: 96),
        waveform: Array(repeating: 0, count: 256),
        beatPulse: 0,
        onsetStrength: 0,
        smoothedVolume: 0,
        smoothedBass: 0,
        smoothedTreble: 0,
        estimatedTempo: nil,
        isSilent: true,
        silenceDuration: 0
    )
}
