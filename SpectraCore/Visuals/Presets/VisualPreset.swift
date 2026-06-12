import Foundation

public enum VisualPresetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case spectrumBars
    case liquidWaveform
    case particleGalaxy
    case neonTunnel
    case minimalWaveform

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .spectrumBars: return "Spectrum Bars"
        case .liquidWaveform: return "Liquid Waveform"
        case .particleGalaxy: return "Particle Galaxy"
        case .neonTunnel: return "Neon Tunnel"
        case .minimalWaveform: return "Minimal Waveform"
        }
    }
}

public enum VisualPresetCategory: String, Codable, Sendable {
    case spectrum
    case waveform
    case particles
    case ambient
}

public enum ColorPalette: String, Codable, CaseIterable, Identifiable, Sendable {
    case aurora
    case magma
    case prism
    case graphite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .aurora: return "Aurora"
        case .magma: return "Magma"
        case .prism: return "Prism"
        case .graphite: return "Graphite"
        }
    }
}

public struct PresetSettings: Codable, Equatable, Sendable {
    public var intensity: Double
    public var sensitivity: Double
    public var palette: ColorPalette
    public var smoothing: Double
    public var motionAmount: Double
    public var glowAmount: Double
    public var beatReactivity: Double
    public var reduceMotion: Bool

    public init(
        intensity: Double = 0.78,
        sensitivity: Double = 0.72,
        palette: ColorPalette = .aurora,
        smoothing: Double = 0.62,
        motionAmount: Double = 0.72,
        glowAmount: Double = 0.64,
        beatReactivity: Double = 0.82,
        reduceMotion: Bool = false
    ) {
        self.intensity = intensity
        self.sensitivity = sensitivity
        self.palette = palette
        self.smoothing = smoothing
        self.motionAmount = motionAmount
        self.glowAmount = glowAmount
        self.beatReactivity = beatReactivity
        self.reduceMotion = reduceMotion
    }

    public static let `default` = PresetSettings()
}

public struct VisualPresetDescriptor: Identifiable, Equatable, Sendable {
    public let id: VisualPresetID
    public let name: String
    public let description: String
    public let category: VisualPresetCategory
    public let defaultSettings: PresetSettings

    public init(
        id: VisualPresetID,
        name: String,
        description: String,
        category: VisualPresetCategory,
        defaultSettings: PresetSettings = .default
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.defaultSettings = defaultSettings
    }
}

public protocol VisualPreset {
    var descriptor: VisualPresetDescriptor { get }
    func update(deltaTime: TimeInterval, audioFrame: VisualAudioFrame)
}
