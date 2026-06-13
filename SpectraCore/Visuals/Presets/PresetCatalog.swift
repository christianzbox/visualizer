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
    ] + worldPresets

    public static func descriptor(for id: VisualPresetID) -> VisualPresetDescriptor {
        presets.first { $0.id == id } ?? presets[0]
    }

    private static let worldPresets: [VisualPresetDescriptor] = [
        worldPreset(.forestCanopyFlight, "Dense green canopy flight with layered trees, mist, and soft bass-lit clearings.", .aurora, 0.78, 0.58, 0.72),
        worldPreset(.riverValleyFlight, "Low flight through a winding river valley with forested banks and reflective water paths.", .aurora, 0.80, 0.60, 0.74),
        worldPreset(.alpinePass, "High mountain pass with snow caps, cliffs, and bright atmospheric fog.", .graphite, 0.82, 0.58, 0.70),
        worldPreset(.stormRidge, "Dark ridgeline flight with heavier clouds, sharper peaks, and thunder-like bass pulses.", .magma, 0.80, 0.56, 0.68),
        scenicPreset(.stainedGlassCathedral, "A giant stained-glass rose window with pulsing panels, light beams, and cathedral arches.", .prism, 0.82, 0.54, 0.42),
        worldPreset(.desertDunes, "Open desert dune traversal with wide horizons, city mirages, and rolling sand ridges.", .magma, 0.78, 0.54, 0.66),
        worldPreset(.canyonRun, "Fast canyon corridor with layered red rock, river cuts, and treble-lit cliff faces.", .magma, 0.82, 0.58, 0.72),
        worldPreset(.glacialFjord, "Icy fjord flight with cold peaks, water channels, and glassy blue mineral highlights.", .graphite, 0.80, 0.54, 0.68),
        worldPreset(.coastalCliffs, "Coastal cliff run over water, green ridges, and hazy horizon light.", .aurora, 0.80, 0.58, 0.72),
        worldPreset(.volcanicBadlands, "Volcanic terrain with dark rock, lava seams, and bass-reactive red glow.", .magma, 0.84, 0.58, 0.70),
        scenicPreset(.clockworkAtrium, "Interlocking clockwork wheels, pendulums, and brass arcs ticking to the beat.", .magma, 0.80, 0.50, 0.48),
        worldPreset(.redwoodTrail, "Tall redwood corridor with huge trunks, shadowed valleys, and deep forest color.", .aurora, 0.82, 0.56, 0.68),
        scenicPreset(.orbitalMechanics, "Planets, orbit trails, satellites, and gravity arcs drifting in a music-driven observatory.", .graphite, 0.78, 0.50, 0.42),
        shaderPreset(.underwaterReef, "A deep reef shader with sonar rings, caustic light sheets, bubbles, and plant silhouettes.", .aurora, 0.76, 0.52, 0.46),
        shaderPreset(.subwayRush, "A perspective subway tunnel shader with rushing rails, platform lights, and passing train bands.", .graphite, 0.82, 0.54, 0.72),
        shaderPreset(.vinylOrbit, "A turntable shader with rotating grooves, label pulses, tonearm sweeps, and dust glints.", .magma, 0.78, 0.50, 0.50),
        worldPreset(.rainforestTemple, "Rainforest temple flythrough with dense vegetation, ruins, and glowing stone paths.", .aurora, 0.82, 0.56, 0.68),
        worldPreset(.islandArchipelago, "Island-hopping flight over water channels, cliffs, and tropical green ridges.", .aurora, 0.80, 0.56, 0.70),
        worldPreset(.neonCityFlyover, "Night city flyover with skyline blocks, neon windows, roads, and audio-lit towers.", .prism, 0.84, 0.58, 0.70),
        scenicPreset(.lanternFestival, "Floating lanterns rising through layered night air with bass-warmed glow.", .magma, 0.76, 0.48, 0.38),
        shaderPreset(.rainWindow, "A rain-on-glass shader with smeared city lights, pane seams, and sliding water trails.", .graphite, 0.74, 0.48, 0.34),
        shaderPreset(.moonBase, "A lunar scan shader with crater fields, base modules, antennae, stars, and low-gravity pulses.", .graphite, 0.78, 0.50, 0.40),
        scenicPreset(.kineticSculpture, "Museum-scale mobiles, suspended discs, rods, and counterweights moving like audio sculpture.", .prism, 0.80, 0.52, 0.46),
        worldPreset(.megaCityGrid, "Massive grid city with tall towers, road canyons, and beat-reactive window fields.", .prism, 0.86, 0.58, 0.72),
        shaderPreset(.danceFloorSilhouettes, "A club-stage shader with crowd silhouettes, volumetric beams, strobes, and floor tiles.", .prism, 0.84, 0.54, 0.58),
        shaderPreset(.dataStorm, "A full-screen data storm shader with digital rain, glitch bars, lightning paths, and scan breaks.", .aurora, 0.82, 0.54, 0.54),
        shaderPreset(.lavaForge, "A molten forge shader with cellular magma, furnace arcs, crack networks, and flying sparks.", .magma, 0.84, 0.54, 0.48),
        worldPreset(.mountainCitadel, "Mountain citadel route with fortified ridges, high towers, and glowing roads.", .aurora, 0.84, 0.56, 0.70),
        worldPreset(.floatingCity, "Fantasy floating-city flight with elevated terrain, towers, and luminous sky haze.", .prism, 0.84, 0.56, 0.70),
        scenicPreset(.paperCutTheater, "Layered paper-cut scenery, sliding stage flats, shadows, and audio-reactive spotlight sweeps.", .aurora, 0.76, 0.48, 0.34),
        shaderPreset(.neonCircuitBoard, "A macro PCB shader with layered traces, glowing nodes, packet pulses, and scanner sweeps.", .prism, 0.80, 0.52, 0.44),
        scenicPreset(.signalGarden, "Abstract stems, blooms, firefly-like points, and swaying color fields grown by the spectrum.", .aurora, 0.78, 0.52, 0.42),
        shaderPreset(.skylineEqualizer, "A pixel-city shader where towers, windows, streets, and rooftop signs become an equalizer.", .magma, 0.80, 0.54, 0.48),
        worldPreset(.templeRuins, "Ancient temple valley with stone blocks, forest growth, and bass-lit ruin paths.", .aurora, 0.82, 0.54, 0.66),
        worldPreset(.spaceportDawn, "Dawn spaceport with runway corridors, towers, and futuristic city silhouettes.", .prism, 0.84, 0.56, 0.70)
    ]

    private static func worldPreset(
        _ id: VisualPresetID,
        _ description: String,
        _ palette: ColorPalette,
        _ intensity: Double,
        _ sensitivity: Double,
        _ motion: Double
    ) -> VisualPresetDescriptor {
        VisualPresetDescriptor(
            id: id,
            name: id.name,
            description: description,
            category: .journey,
            defaultSettings: PresetSettings(
                intensity: intensity,
                sensitivity: sensitivity,
                palette: palette,
                smoothing: 0.80,
                motionAmount: motion,
                glowAmount: 0.76,
                beatReactivity: 0.56
            )
        )
    }

    private static func scenicPreset(
        _ id: VisualPresetID,
        _ description: String,
        _ palette: ColorPalette,
        _ intensity: Double,
        _ sensitivity: Double,
        _ motion: Double
    ) -> VisualPresetDescriptor {
        VisualPresetDescriptor(
            id: id,
            name: id.name,
            description: description,
            category: .journey,
            defaultSettings: PresetSettings(
                intensity: intensity,
                sensitivity: sensitivity,
                palette: palette,
                smoothing: 0.86,
                motionAmount: motion,
                glowAmount: 0.72,
                beatReactivity: 0.48
            )
        )
    }

    private static func shaderPreset(
        _ id: VisualPresetID,
        _ description: String,
        _ palette: ColorPalette,
        _ intensity: Double,
        _ sensitivity: Double,
        _ motion: Double
    ) -> VisualPresetDescriptor {
        VisualPresetDescriptor(
            id: id,
            name: id.name,
            description: description,
            category: .journey,
            defaultSettings: PresetSettings(
                intensity: intensity,
                sensitivity: sensitivity,
                palette: palette,
                smoothing: 0.88,
                motionAmount: motion,
                glowAmount: 0.82,
                beatReactivity: 0.42
            )
        )
    }
}
