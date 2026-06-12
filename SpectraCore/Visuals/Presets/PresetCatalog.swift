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
        )
    ]

    public static func descriptor(for id: VisualPresetID) -> VisualPresetDescriptor {
        presets.first { $0.id == id } ?? presets[0]
    }
}
