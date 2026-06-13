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
    case autumnForest
    case desertDunes
    case canyonRun
    case glacialFjord
    case coastalCliffs
    case volcanicBadlands
    case bambooRain
    case redwoodTrail
    case moonlitMarsh
    case savannaSunset
    case tundraLights
    case cherryBlossomValley
    case rainforestTemple
    case islandArchipelago
    case neonCityFlyover
    case rainCity
    case sunsetSkyline
    case cyberHarbor
    case oldTownCanals
    case megaCityGrid
    case rooftopChase
    case industrialDocks
    case desertCity
    case mountainCitadel
    case floatingCity
    case crystalMesa
    case snowVillage
    case auroraPeaks
    case riverCity
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
                .forestCanopyFlight, .riverValleyFlight, .alpinePass, .stormRidge, .autumnForest, .desertDunes, .canyonRun, .glacialFjord, .coastalCliffs,
                .volcanicBadlands, .bambooRain, .redwoodTrail, .moonlitMarsh, .savannaSunset, .tundraLights, .cherryBlossomValley, .rainforestTemple,
                .islandArchipelago, .neonCityFlyover, .rainCity, .sunsetSkyline, .cyberHarbor, .oldTownCanals, .megaCityGrid, .rooftopChase,
                .industrialDocks, .desertCity, .mountainCitadel, .floatingCity, .crystalMesa, .snowVillage, .auroraPeaks, .riverCity, .templeRuins,
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
                .forestCanopyFlight, .riverValleyFlight, .alpinePass, .stormRidge, .autumnForest, .desertDunes, .canyonRun, .glacialFjord, .coastalCliffs,
                .volcanicBadlands, .bambooRain, .redwoodTrail, .moonlitMarsh, .savannaSunset, .tundraLights, .cherryBlossomValley, .rainforestTemple,
                .islandArchipelago, .neonCityFlyover, .rainCity, .sunsetSkyline, .cyberHarbor, .oldTownCanals, .megaCityGrid, .rooftopChase,
                .industrialDocks, .desertCity, .mountainCitadel, .floatingCity, .crystalMesa, .snowVillage, .auroraPeaks, .riverCity, .templeRuins,
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

    public var meshWorldVariant: Int? {
        switch self {
        case .terrainFlight: return 0
        case .skyRealmFlight: return 1
        case .forestCanopyFlight: return 2
        case .riverValleyFlight: return 3
        case .alpinePass: return 4
        case .stormRidge: return 5
        case .autumnForest: return 6
        case .desertDunes: return 7
        case .canyonRun: return 8
        case .glacialFjord: return 9
        case .coastalCliffs: return 10
        case .volcanicBadlands: return 11
        case .bambooRain: return 12
        case .redwoodTrail: return 13
        case .moonlitMarsh: return 14
        case .savannaSunset: return 15
        case .tundraLights: return 16
        case .cherryBlossomValley: return 17
        case .rainforestTemple: return 18
        case .islandArchipelago: return 19
        case .neonCityFlyover: return 20
        case .rainCity: return 21
        case .sunsetSkyline: return 22
        case .cyberHarbor: return 23
        case .oldTownCanals: return 24
        case .megaCityGrid: return 25
        case .rooftopChase: return 26
        case .industrialDocks: return 27
        case .desertCity: return 28
        case .mountainCitadel: return 29
        case .floatingCity: return 30
        case .crystalMesa: return 31
        case .snowVillage: return 32
        case .auroraPeaks: return 33
        case .riverCity: return 34
        case .templeRuins: return 35
        case .spaceportDawn: return 36
        case .spectrumBars, .liquidWaveform, .particleGalaxy, .neonTunnel, .minimalWaveform, .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse,
                .phoenixField, .mandelboxFlight, .nebulaVoyage, .crystalCavern:
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
