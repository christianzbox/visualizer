import Foundation
import Metal
import SpectraCore

enum DiagnosticFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message): return message
        }
    }
}

@main
struct SpectraDiagnostics {
    static func main() async {
        do {
            try testFFT()
            try testBandMapping()
            try testSilenceDetection()
            try testMalformedAnalysisInput()
            try testBeatDetection()
            try testSmoothing()
            try testRingBuffer()
            try testMetalShaderCompilation()
            try await testSignalGeneration()
            try testSettingsPersistence()
            try testPresetCatalog()
            try testCaptureErrors()
            print("SpectraDiagnostics: all checks passed")
        } catch {
            fputs("SpectraDiagnostics failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testFFT() throws {
        let analyzer = FFTAnalyzer(windowSize: 2_048, bandCount: 64)
        let bass = analyzer.analyze(samples: sineWave(frequency: 95, count: 2_048), sampleRate: 48_000)
        let lowMid = analyzer.analyze(samples: sineWave(frequency: 440, count: 2_048), sampleRate: 48_000)

        try expect(bass.bandEnergies.bass > bass.bandEnergies.mids, "95 Hz tone should emphasize bass")
        try expect(lowMid.bandEnergies.lowMids > lowMid.bandEnergies.treble, "440 Hz tone should emphasize low mids over treble")
        try expect(lowMid.spectrumBands.count == 64, "FFT should produce requested visual band count")
    }

    private static func testBandMapping() throws {
        let fftSize = 2_048
        let sampleRate = 48_000.0
        var magnitudes = Array(repeating: Float(0), count: fftSize / 2)
        let bin = Int(100 / (sampleRate / Double(fftSize)))
        magnitudes[bin] = 1

        let bass = BandEnergyAnalyzer.energy(
            in: FrequencyBand(name: "Bass", lowFrequency: 60, highFrequency: 250),
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize
        )
        let treble = BandEnergyAnalyzer.energy(
            in: FrequencyBand(name: "Treble", lowFrequency: 6_000, highFrequency: 16_000),
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize
        )
        try expect(bass > treble, "Frequency-to-band mapping should route 100 Hz into bass")
    }

    private static func testSilenceDetection() throws {
        let engine = AudioAnalysisEngine()
        var frame = VisualAudioFrame.silent
        for index in 0..<40 {
            frame = engine.process(AudioBufferFrame(
                timestamp: Double(index) * 0.02,
                sampleRate: 48_000,
                channelCount: 1,
                frames: 512,
                samples: Array(repeating: 0, count: 512),
                sourceId: "silence"
            ))
        }
        try expect(frame.isSilent, "Sustained zero input should become silent")
        try expect(frame.silenceDuration > 0.25, "Silence duration should accumulate after hold time")
    }

    private static func testBeatDetection() throws {
        var detector = BeatDetector(historySize: 12, thresholdMultiplier: 1.28, minimumBeatInterval: 0.1)
        var maxPulse: Float = 0
        for index in 0..<36 {
            let isPulse = index == 10 || index == 24
            let pulse = detector.process(
                energy: isPulse ? 0.9 : 0.08,
                bassEnergy: isPulse ? 0.92 : 0.1,
                onsetStrength: isPulse ? 0.55 : 0.02,
                timestamp: Double(index) * 0.05
            )
            maxPulse = max(maxPulse, pulse)
        }
        try expect(maxPulse > 0.8, "Transient bass pulse should trigger beat detector")
    }

    private static func testMalformedAnalysisInput() throws {
        let engine = AudioAnalysisEngine()
        let frame = engine.process(AudioBufferFrame(
            timestamp: 0,
            sampleRate: 48_000,
            channelCount: 0,
            frames: 0,
            samples: [],
            sourceId: "empty"
        ))
        try expect(frame.isSilent, "Malformed empty input should produce a silent visual frame")
        try expect(frame.spectrumBands.count == 96, "Silent fallback should preserve visual band shape")
    }

    private static func testSmoothing() throws {
        var smoother = ExponentialSmoother(initialValue: 0, smoothing: 0.5)
        try expect(abs(smoother.process(1) - 0.5) < 0.0001, "Exponential smoothing first step mismatch")
        try expect(abs(smoother.process(1) - 0.75) < 0.0001, "Exponential smoothing second step mismatch")

        var envelope = AttackReleaseEnvelope(initialValue: 0, attack: 0.2, release: 0.9)
        let attack = envelope.process(1, deltaTime: 1.0 / 60.0)
        let release = envelope.process(0, deltaTime: 1.0 / 60.0)
        try expect(attack > 0.7, "Envelope should respond quickly to attack")
        try expect(release > 0.6 && release < attack, "Envelope should release slower than attack")
    }

    private static func testSignalGeneration() async throws {
        let engine = TestSignalCaptureEngine(signalType: .beatPattern, sampleRate: 48_000, channelCount: 1, bufferSize: 256)
        let box = FrameBox()
        engine.setAudioBufferHandler { frame in
            box.store(frame)
        }
        try await engine.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        await engine.stop()

        guard let frame = box.load() else {
            throw DiagnosticFailure.expectation("Test signal should produce at least one buffer")
        }
        try expect(frame.samples.count == 256, "Test signal buffer should match configured frame count")
        try expect((frame.samples.map { abs($0) }.max() ?? 0) > 0.02, "Beat pattern should generate non-zero samples")
    }

    private static func testRingBuffer() throws {
        let buffer = AudioRingBuffer(capacity: 5)
        buffer.append([1, 2, 3])
        buffer.append([4, 5, 6, 7])
        try expect(buffer.latest(5) == [3, 4, 5, 6, 7], "Ring buffer should retain newest samples")
        buffer.clear()
        try expect(buffer.latest(5).isEmpty, "Ring buffer clear should remove samples")
    }

    private static func testMetalShaderCompilation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw DiagnosticFailure.expectation("Diagnostics require a Metal device")
        }
        let shaderURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Spectra/Visuals/Metal/Shaders.metal")
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        try expect(library.makeFunction(name: "spectra_vertex") != nil, "Metal shader should expose spectra_vertex")
        try expect(library.makeFunction(name: "spectra_fragment") != nil, "Metal shader should expose spectra_fragment")
        try expect(library.makeFunction(name: "spectra_fractal_fragment") != nil, "Metal shader should expose spectra_fractal_fragment")
        try expect(library.makeFunction(name: "terrain_vertex") != nil, "Metal shader should expose terrain_vertex")
        try expect(library.makeFunction(name: "terrain_fragment") != nil, "Metal shader should expose terrain_fragment")
    }

    private static func testSettingsPersistence() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spectra-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(url: url)
        var settings = UserSettings.default
        settings.selectedPreset = .particleGalaxy
        settings.presetSettings.intensity = 0.42
        settings.captureMode = .testSignal
        store.save(settings)

        let loaded = store.load()
        try expect(loaded.selectedPreset == .particleGalaxy, "Settings should persist selected preset")
        try expect(abs(loaded.presetSettings.intensity - 0.42) < 0.0001, "Settings should persist preset intensity")
    }

    private static func testPresetCatalog() throws {
        let ids = PresetCatalog.presets.map(\.id)
        try expect(Set(ids) == Set(VisualPresetID.allCases), "Preset catalog should expose every preset")
        try expect(ids.count == Set(ids).count, "Preset catalog should not contain duplicate IDs")
        for preset in PresetCatalog.presets {
            try expect((0...1).contains(preset.defaultSettings.intensity), "\(preset.name) intensity out of range")
            try expect((0...1).contains(preset.defaultSettings.sensitivity), "\(preset.name) sensitivity out of range")
        }
        let fractalPresets = PresetCatalog.presets.filter { $0.category == .fractal }
        let fractalModes = fractalPresets.compactMap { $0.id.fractalMode }
        try expect(fractalPresets.count == 6, "Preset catalog should expose six real fractal choices")
        try expect(fractalModes.count == fractalPresets.count, "Every fractal preset should have a shader mode")
        try expect(Set(fractalModes) == Set(0...5), "Fractal presets should map to distinct shader formulas")
        let shaderPresets = PresetCatalog.presets.filter { $0.id.usesFullscreenShader }
        let shaderModes = shaderPresets.compactMap { $0.id.fullscreenShaderMode }
        try expect(shaderPresets.count == 8, "Preset catalog should expose eight full-screen shader choices")
        try expect(Set(shaderModes) == Set(0...7), "Full-screen shader presets should map to distinct shader modes")
        let meshPresets = PresetCatalog.presets.filter { $0.id.usesMeshWorld }
        try expect(Set(meshPresets.map(\.id)) == [.terrainFlight, .skyRealmFlight], "Mesh world presets should be explicit")
    }

    private static func testCaptureErrors() throws {
        let denied = AudioCaptureError.permissionDenied
        try expect(denied.recoverySuggestion?.contains("Test Signal Mode") == true, "Permission denial should mention fallback")

        let unsupported = AudioCaptureError.unsupportedOS("Unsupported")
        try expect(unsupported.recoverySuggestion?.contains("macOS 13") == true, "Unsupported OS should mention required version")
    }

    private static func sineWave(frequency: Double, count: Int) -> [Float] {
        (0..<count).map { index in
            Float(sin((Double(index) / 48_000.0) * frequency * Double.pi * 2) * 0.8)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw DiagnosticFailure.expectation(message)
        }
    }
}

private final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: AudioBufferFrame?

    func store(_ frame: AudioBufferFrame) {
        lock.lock()
        self.frame = frame
        lock.unlock()
    }

    func load() -> AudioBufferFrame? {
        lock.lock()
        let output = frame
        lock.unlock()
        return output
    }
}
