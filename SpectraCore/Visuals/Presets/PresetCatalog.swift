import Foundation

public enum PresetCatalog {
    public static let presets: [VisualPresetDescriptor] = [
        VisualPresetDescriptor(
            id: .spectrumBars,
            name: VisualPresetID.spectrumBars.name,
            description: "Polished logarithmic frequency bars with bass glow and treble detail.",
            category: .spectrum
        ),
        VisualPresetDescriptor(
            id: .liquidWaveform,
            name: VisualPresetID.liquidWaveform.name,
            description: "Smooth horizontal liquid waveform driven by RMS, waveform, and bass.",
            category: .waveform,
            defaultSettings: PresetSettings(intensity: 0.72, sensitivity: 0.76, palette: .prism)
        ),
        VisualPresetDescriptor(
            id: .particleGalaxy,
            name: VisualPresetID.particleGalaxy.name,
            description: "Cinematic particle field that expands on beats and shimmers on treble.",
            category: .particles,
            defaultSettings: PresetSettings(intensity: 0.86, sensitivity: 0.78, palette: .magma, motionAmount: 0.82)
        ),
        VisualPresetDescriptor(
            id: .neonTunnel,
            name: VisualPresetID.neonTunnel.name,
            description: "Audio-reactive radial tunnel with beat depth and treble line detail.",
            category: .ambient,
            defaultSettings: PresetSettings(intensity: 0.80, sensitivity: 0.74, palette: .prism, motionAmount: 0.78, glowAmount: 0.68)
        ),
        VisualPresetDescriptor(
            id: .minimalWaveform,
            name: VisualPresetID.minimalWaveform.name,
            description: "Quiet voice-friendly waveform with restrained motion and low visual density.",
            category: .waveform,
            defaultSettings: PresetSettings(intensity: 0.48, sensitivity: 0.66, palette: .graphite, motionAmount: 0.32, glowAmount: 0.28)
        ),
        VisualPresetDescriptor(
            id: .mandelbrotBloom,
            name: VisualPresetID.mandelbrotBloom.name,
            description: "Classic Mandelbrot escape-time bloom with bass zoom, mid rotation, and treble color bands.",
            category: .fractal,
            defaultSettings: PresetSettings(intensity: 0.82, sensitivity: 0.74, palette: .prism, motionAmount: 0.54, glowAmount: 0.72, beatReactivity: 0.86)
        ),
        VisualPresetDescriptor(
            id: .juliaVortex,
            name: VisualPresetID.juliaVortex.name,
            description: "Julia-set vortex whose complex seed follows the audio envelope and onset pulse.",
            category: .fractal,
            defaultSettings: PresetSettings(intensity: 0.78, sensitivity: 0.76, palette: .aurora, motionAmount: 0.64, glowAmount: 0.68, beatReactivity: 0.80)
        ),
        VisualPresetDescriptor(
            id: .burningShip,
            name: VisualPresetID.burningShip.name,
            description: "Burning Ship fractal with rectified complex folds that surge with low-frequency energy.",
            category: .fractal,
            defaultSettings: PresetSettings(intensity: 0.84, sensitivity: 0.72, palette: .magma, motionAmount: 0.48, glowAmount: 0.76, beatReactivity: 0.90)
        ),
        VisualPresetDescriptor(
            id: .tricornPulse,
            name: VisualPresetID.tricornPulse.name,
            description: "Tricorn conjugate-set pulse with mirrored structures driven by mids and beat pressure.",
            category: .fractal,
            defaultSettings: PresetSettings(intensity: 0.76, sensitivity: 0.70, palette: .prism, motionAmount: 0.58, glowAmount: 0.62, beatReactivity: 0.78)
        ),
        VisualPresetDescriptor(
            id: .phoenixField,
            name: VisualPresetID.phoenixField.name,
            description: "Phoenix fractal field with memory feedback mapped to treble detail and bass expansion.",
            category: .fractal,
            defaultSettings: PresetSettings(intensity: 0.80, sensitivity: 0.74, palette: .aurora, motionAmount: 0.60, glowAmount: 0.70, beatReactivity: 0.84)
        ),
        VisualPresetDescriptor(
            id: .mandelboxFlight,
            name: VisualPresetID.mandelboxFlight.name,
            description: "Folded-space fractal traversal with bass-driven depth and treble-lit crystalline edges.",
            category: .fractal,
            defaultSettings: PresetSettings(intensity: 0.86, sensitivity: 0.76, palette: .prism, motionAmount: 0.72, glowAmount: 0.76, beatReactivity: 0.88)
        ),
        VisualPresetDescriptor(
            id: .terrainFlight,
            name: VisualPresetID.terrainFlight.name,
            description: "Depth-rendered 3D landscape flight with mesh mountains, cinematic fog, and subtle audio lighting.",
            category: .journey,
            defaultSettings: PresetSettings(intensity: 0.82, sensitivity: 0.72, palette: .aurora, motionAmount: 0.80, glowAmount: 0.66, beatReactivity: 0.78)
        ),
        VisualPresetDescriptor(
            id: .nebulaVoyage,
            name: VisualPresetID.nebulaVoyage.name,
            description: "Volumetric tunnel voyage with flowing nebula bands, star dust, and beat-reactive forward motion.",
            category: .journey,
            defaultSettings: PresetSettings(intensity: 0.78, sensitivity: 0.68, palette: .magma, smoothing: 0.74, motionAmount: 0.74, glowAmount: 0.78, beatReactivity: 0.68)
        ),
        VisualPresetDescriptor(
            id: .skyRealmFlight,
            name: VisualPresetID.skyRealmFlight.name,
            description: "Depth-rendered high-fantasy flight over elevated realms, luminous ridges, and atmospheric haze.",
            category: .journey,
            defaultSettings: PresetSettings(intensity: 0.80, sensitivity: 0.66, palette: .aurora, smoothing: 0.78, motionAmount: 0.70, glowAmount: 0.72, beatReactivity: 0.62)
        ),
        VisualPresetDescriptor(
            id: .crystalCavern,
            name: VisualPresetID.crystalCavern.name,
            description: "Game-like cavern flythrough with parallax crystal walls, glowing mineral seams, and bass-lit depth.",
            category: .journey,
            defaultSettings: PresetSettings(intensity: 0.82, sensitivity: 0.64, palette: .prism, smoothing: 0.80, motionAmount: 0.68, glowAmount: 0.80, beatReactivity: 0.60)
        )
    ]

    public static func descriptor(for id: VisualPresetID) -> VisualPresetDescriptor {
        presets.first { $0.id == id } ?? presets[0]
    }
}
