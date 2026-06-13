import Foundation

public enum VisualPresetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case spectrumBars
    case liquidWaveform
    case particleGalaxy
    case neonTunnel
    case minimalWaveform
    case mandelbrotBloom
    case juliaVortex
    case burningShip
    case tricornPulse
    case phoenixField
    case mandelboxFlight
    case terrainFlight
    case nebulaVoyage
    case skyRealmFlight
    case crystalCavern
    case forestCanopyFlight
    case riverValleyFlight
    case alpinePass
    case stormRidge
    case stainedGlassCathedral
    case desertDunes
    case canyonRun
    case glacialFjord
    case coastalCliffs
    case volcanicBadlands
    case clockworkAtrium
    case redwoodTrail
    case orbitalMechanics
    case underwaterReef
    case subwayRush
    case vinylOrbit
    case rainforestTemple
    case islandArchipelago
    case neonCityFlyover
    case lanternFestival
    case rainWindow
    case moonBase
    case kineticSculpture
    case megaCityGrid
    case danceFloorSilhouettes
    case dataStorm
    case lavaForge
    case mountainCitadel
    case floatingCity
    case paperCutTheater
    case neonCircuitBoard
    case signalGarden
    case skylineEqualizer
    case templeRuins
    case spaceportDawn

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .spectrumBars: return "Spectrum Bars"
        case .liquidWaveform: return "Liquid Waveform"
        case .particleGalaxy: return "Particle Galaxy"
        case .neonTunnel: return "Neon Tunnel"
        case .minimalWaveform: return "Minimal Waveform"
        case .mandelbrotBloom: return "Mandelbrot Bloom"
        case .juliaVortex: return "Julia Vortex"
        case .burningShip: return "Burning Ship"
        case .tricornPulse: return "Tricorn Pulse"
        case .phoenixField: return "Phoenix Field"
        case .mandelboxFlight: return "Mandelbox Flight"
        case .terrainFlight: return "Terrain Flight"
        case .nebulaVoyage: return "Nebula Voyage"
        case .skyRealmFlight: return "Sky Realm Flight"
        case .crystalCavern: return "Crystal Cavern"
        default: return Self.humanized(rawValue)
        }
    }

    public var fractalMode: Int? {
        switch self {
        case .mandelbrotBloom: return 0
        case .juliaVortex: return 1
        case .burningShip: return 2
        case .tricornPulse: return 3
        case .phoenixField: return 4
        case .mandelboxFlight: return 5
        case .spectrumBars, .liquidWaveform, .particleGalaxy, .neonTunnel, .minimalWaveform, .terrainFlight, .nebulaVoyage, .skyRealmFlight, .crystalCavern,
                .forestCanopyFlight, .riverValleyFlight, .alpinePass, .stormRidge, .stainedGlassCathedral, .desertDunes, .canyonRun, .glacialFjord, .coastalCliffs,
                .volcanicBadlands, .clockworkAtrium, .redwoodTrail, .orbitalMechanics, .underwaterReef, .subwayRush, .vinylOrbit, .rainforestTemple,
                .islandArchipelago, .neonCityFlyover, .lanternFestival, .rainWindow, .moonBase, .kineticSculpture, .megaCityGrid, .danceFloorSilhouettes,
                .dataStorm, .lavaForge, .mountainCitadel, .floatingCity, .paperCutTheater, .neonCircuitBoard, .signalGarden, .skylineEqualizer, .templeRuins,
                .spaceportDawn:
            return nil
        }
    }

    public var fullscreenShaderMode: Int? {
        switch self {
        case .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse, .phoenixField, .mandelboxFlight:
            return fractalMode
        case .nebulaVoyage: return 6
        case .crystalCavern: return 7
        case .spectrumBars, .liquidWaveform, .particleGalaxy, .neonTunnel, .minimalWaveform, .terrainFlight, .skyRealmFlight,
                .forestCanopyFlight, .riverValleyFlight, .alpinePass, .stormRidge, .stainedGlassCathedral, .desertDunes, .canyonRun, .glacialFjord, .coastalCliffs,
                .volcanicBadlands, .clockworkAtrium, .redwoodTrail, .orbitalMechanics, .underwaterReef, .subwayRush, .vinylOrbit, .rainforestTemple,
                .islandArchipelago, .neonCityFlyover, .lanternFestival, .rainWindow, .moonBase, .kineticSculpture, .megaCityGrid, .danceFloorSilhouettes,
                .dataStorm, .lavaForge, .mountainCitadel, .floatingCity, .paperCutTheater, .neonCircuitBoard, .signalGarden, .skylineEqualizer, .templeRuins,
                .spaceportDawn:
            return nil
        }
    }

    public var usesFullscreenShader: Bool {
        fullscreenShaderMode != nil
    }

    public var usesMeshWorld: Bool {
        meshWorldVariant != nil
    }

    public var usesScenicRenderer: Bool {
        scenicMode != nil
    }

    public var meshWorldVariant: Int? {
        switch self {
        case .terrainFlight: return 0
        case .skyRealmFlight: return 1
        case .forestCanopyFlight: return 2
        case .riverValleyFlight: return 3
        case .alpinePass: return 4
        case .stormRidge: return 5
        case .desertDunes: return 6
        case .canyonRun: return 7
        case .glacialFjord: return 8
        case .coastalCliffs: return 9
        case .volcanicBadlands: return 10
        case .redwoodTrail: return 11
        case .rainforestTemple: return 12
        case .islandArchipelago: return 13
        case .neonCityFlyover: return 14
        case .megaCityGrid: return 15
        case .mountainCitadel: return 16
        case .floatingCity: return 17
        case .templeRuins: return 18
        case .spaceportDawn: return 19
        case .spectrumBars, .liquidWaveform, .particleGalaxy, .neonTunnel, .minimalWaveform, .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse,
                .phoenixField, .mandelboxFlight, .nebulaVoyage, .crystalCavern, .stainedGlassCathedral, .clockworkAtrium, .orbitalMechanics,
                .underwaterReef, .subwayRush, .vinylOrbit, .lanternFestival, .rainWindow, .moonBase, .kineticSculpture, .danceFloorSilhouettes,
                .dataStorm, .lavaForge, .paperCutTheater, .neonCircuitBoard, .signalGarden, .skylineEqualizer:
            return nil
        }
    }

    public var scenicMode: Int? {
        switch self {
        case .stainedGlassCathedral: return 0
        case .clockworkAtrium: return 1
        case .orbitalMechanics: return 2
        case .underwaterReef: return 3
        case .subwayRush: return 4
        case .vinylOrbit: return 5
        case .lanternFestival: return 6
        case .rainWindow: return 7
        case .moonBase: return 8
        case .kineticSculpture: return 9
        case .danceFloorSilhouettes: return 10
        case .dataStorm: return 11
        case .lavaForge: return 12
        case .paperCutTheater: return 13
        case .neonCircuitBoard: return 14
        case .signalGarden: return 15
        case .skylineEqualizer: return 16
        case .spectrumBars, .liquidWaveform, .particleGalaxy, .neonTunnel, .minimalWaveform, .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse,
                .phoenixField, .mandelboxFlight, .terrainFlight, .nebulaVoyage, .skyRealmFlight, .crystalCavern, .forestCanopyFlight, .riverValleyFlight,
                .alpinePass, .stormRidge, .desertDunes, .canyonRun, .glacialFjord, .coastalCliffs, .volcanicBadlands, .redwoodTrail, .rainforestTemple,
                .islandArchipelago, .neonCityFlyover, .megaCityGrid, .mountainCitadel, .floatingCity, .templeRuins, .spaceportDawn:
            return nil
        }
    }

    private static func humanized(_ rawValue: String) -> String {
        rawValue.reduce(into: "") { output, character in
            if character.isUppercase {
                output.append(" ")
            }
            output.append(character)
        }
        .split(separator: " ")
        .map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }
        .joined(separator: " ")
    }
}

public enum VisualPresetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case spectrum
    case waveform
    case particles
    case ambient
    case fractal
    case journey

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .spectrum: return "Spectrum"
        case .waveform: return "Waveform"
        case .particles: return "Particles"
        case .ambient: return "Ambient"
        case .fractal: return "Fractals"
        case .journey: return "Journeys"
        }
    }
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
