import Metal
import MetalKit
import SpectraCore
import simd

private struct FractalUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var rms: Float
    var volume: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var beat: Float
    var intensity: Float
    var sensitivity: Float
    var motion: Float
    var glow: Float
    var beatReactivity: Float
    var mode: UInt32
    var palette: UInt32
}

private struct RenderSignalState {
    private var volume = AttackReleaseEnvelope(initialValue: 0, attack: 0.16, release: 0.92)
    private var bass = AttackReleaseEnvelope(initialValue: 0, attack: 0.13, release: 0.94)
    private var mid = AttackReleaseEnvelope(initialValue: 0, attack: 0.20, release: 0.92)
    private var highMid = AttackReleaseEnvelope(initialValue: 0, attack: 0.22, release: 0.90)
    private var treble = AttackReleaseEnvelope(initialValue: 0, attack: 0.28, release: 0.88)
    private var beat = AttackReleaseEnvelope(initialValue: 0, attack: 0.08, release: 0.78)
    private var onset = AttackReleaseEnvelope(initialValue: 0, attack: 0.10, release: 0.82)
    private(set) var visualTime: Float = 0

    mutating func process(
        _ frame: VisualAudioFrame,
        settings: PresetSettings,
        deltaTime: TimeInterval
    ) -> VisualAudioFrame {
        let motion = settings.reduceMotion ? Float(0.08) : Float(settings.motionAmount)
        let smoothedVolume = volume.process(max(frame.smoothedVolume, frame.rms * 2.0), deltaTime: deltaTime)
        let smoothedBass = bass.process(max(frame.smoothedBass, frame.bassEnergy), deltaTime: deltaTime)
        let smoothedMid = mid.process(frame.midEnergy, deltaTime: deltaTime)
        let smoothedHighMid = highMid.process(frame.highMidEnergy, deltaTime: deltaTime)
        let smoothedTreble = treble.process(max(frame.smoothedTreble, frame.trebleEnergy), deltaTime: deltaTime)
        let beatTrail = beat.process(max(frame.beatPulse, frame.onsetStrength * 0.42), deltaTime: deltaTime)
        let onsetTrail = onset.process(frame.onsetStrength, deltaTime: deltaTime)

        visualTime += Float(deltaTime) * (
            0.42
            + motion * 0.30
            + smoothedVolume * 0.26
            + smoothedBass * 0.18
            + beatTrail * 0.20
        )

        var output = frame
        output.smoothedVolume = min(1, smoothedVolume)
        output.bassEnergy = min(1, smoothedBass)
        output.smoothedBass = min(1, smoothedBass)
        output.midEnergy = min(1, smoothedMid)
        output.highMidEnergy = min(1, smoothedHighMid)
        output.trebleEnergy = min(1, smoothedTreble)
        output.smoothedTreble = min(1, smoothedTreble)
        output.beatPulse = min(1, beatTrail)
        output.onsetStrength = min(1, onsetTrail)
        return output
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let frameStore: VisualFrameStore
    private var presetProvider: () -> VisualPresetID
    private var settingsProvider: () -> PresetSettings
    private let fpsHandler: (Double) -> Void

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var geometryPipelineState: MTLRenderPipelineState?
    private var fractalPipelineState: MTLRenderPipelineState?
    private var startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()
    private var fpsSampleStart = CACurrentMediaTime()
    private var fpsFrameCount = 0
    private var renderSignalState = RenderSignalState()
    private var reusableVertices: [SpectraVertex] = []
    private var vertexBuffer: MTLBuffer?
    private var vertexCapacity = 0

    init(
        frameStore: VisualFrameStore,
        presetProvider: @escaping () -> VisualPresetID,
        settingsProvider: @escaping () -> PresetSettings,
        fpsHandler: @escaping (Double) -> Void
    ) {
        self.frameStore = frameStore
        self.presetProvider = presetProvider
        self.settingsProvider = settingsProvider
        self.fpsHandler = fpsHandler
        super.init()
    }

    func attach(to view: MTKView) {
        let device = MTLCreateSystemDefaultDevice()
        view.device = device
        view.delegate = self
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        if let library = makeShaderLibrary(for: view) {
            self.geometryPipelineState = makePipeline(for: view, library: library, fragmentFunctionName: "spectra_fragment")
            self.fractalPipelineState = makePipeline(for: view, library: library, fragmentFunctionName: "spectra_fractal_fragment")
        }
    }

    func update(
        presetProvider: @escaping () -> VisualPresetID,
        settingsProvider: @escaping () -> PresetSettings
    ) {
        self.presetProvider = presetProvider
        self.settingsProvider = settingsProvider
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let device,
              let commandQueue,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        let now = CACurrentMediaTime()
        let deltaTime = max(1.0 / 120.0, min(1.0 / 20.0, now - lastFrameTime))
        let rawFrame = frameStore.read()
        let settings = settingsProvider()
        let preset = presetProvider()
        let frame = renderSignalState.process(rawFrame, settings: settings, deltaTime: deltaTime)
        let time = renderSignalState.visualTime + Float(now - startTime) * 0.10
        let usesFullscreenShader = preset.usesFullscreenShader
        reusableVertices.removeAll(keepingCapacity: true)
        appendVertices(
            into: &reusableVertices,
            for: preset,
            frame: frame,
            settings: settings,
            time: time,
            drawableSize: view.drawableSize
        )
        if !usesFullscreenShader {
            applyTraversalTransform(to: &reusableVertices, frame: frame, settings: settings, time: time)
        }
        guard let pipelineState = usesFullscreenShader ? fractalPipelineState : geometryPipelineState else { return }

        let clear = backgroundColor(for: settings.palette, frame: frame)
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(clear.x),
            green: Double(clear.y),
            blue: Double(clear.z),
            alpha: 1
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        if usesFullscreenShader {
            var uniforms = makeFractalUniforms(
                preset: preset,
                frame: frame,
                settings: settings,
                time: time,
                drawableSize: view.drawableSize
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FractalUniforms>.stride, index: 0)
        }
        if !reusableVertices.isEmpty,
           let buffer = ensureVertexBuffer(device: device, vertexCount: reusableVertices.count) {
            let byteCount = MemoryLayout<SpectraVertex>.stride * reusableVertices.count
            reusableVertices.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
                }
            }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: reusableVertices.count)
        }
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        updateFPS()
        lastFrameTime = now
    }

    private func makeShaderLibrary(for view: MTKView) -> MTLLibrary? {
        guard let device = view.device else { return nil }
        do {
            return try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            assertionFailure("Spectra Metal shader compilation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func makePipeline(
        for view: MTKView,
        library: MTLLibrary,
        fragmentFunctionName: String
    ) -> MTLRenderPipelineState? {
        guard let device = view.device else { return nil }
        guard let vertexFunction = library.makeFunction(name: "spectra_vertex"),
              let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            assertionFailure("Spectra Metal shader library is missing \(fragmentFunctionName).")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("Spectra Metal pipeline creation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func appendVertices(
        into vertices: inout [SpectraVertex],
        for preset: VisualPresetID,
        frame: VisualAudioFrame,
        settings: PresetSettings,
        time: Float,
        drawableSize: CGSize
    ) {
        switch preset {
        case .spectrumBars:
            spectrumBars(into: &vertices, frame: frame, settings: settings, time: time)
        case .liquidWaveform:
            liquidWaveform(into: &vertices, frame: frame, settings: settings, time: time)
        case .particleGalaxy:
            particleGalaxy(into: &vertices, frame: frame, settings: settings, time: time)
        case .neonTunnel:
            neonTunnel(into: &vertices, frame: frame, settings: settings, time: time)
        case .minimalWaveform:
            minimalWaveform(into: &vertices, frame: frame, settings: settings, time: time)
        case .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse, .phoenixField, .mandelboxFlight, .terrainFlight, .nebulaVoyage:
            fractalSurface(into: &vertices, drawableSize: drawableSize)
        }
    }

    private func spectrumBars(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let bands = frame.spectrumBands.isEmpty ? VisualAudioFrame.silent.spectrumBands : frame.spectrumBands
        let count = min(72, bands.count)
        let sensitivity = Float(settings.sensitivity)
        let intensity = Float(settings.intensity)
        let beat = frame.beatPulse * Float(settings.beatReactivity)
        let palette = paletteColors(settings.palette)
        vertices.reserveCapacity(count * 18 + 160)
        appendCinematicBackdrop(into: &vertices, frame: frame, settings: settings, time: time, palette: palette)

        for index in 0..<count {
            let x0 = -0.94 + (Float(index) / Float(count)) * 1.88
            let x1 = -0.94 + (Float(index + 1) / Float(count)) * 1.88 - 0.006
            let position = Float(index) / Float(max(1, count - 1))
            let energy = pow(min(1, bands[index] * sensitivity * 1.58), 0.66)
            let orchestralLift = 0.08 * frame.midEnergy + 0.04 * frame.highMidEnergy
            let height = max(0.018, energy * 1.34 * intensity + orchestralLift)
            let y0: Float = -0.78
            let y1 = min(0.90, y0 + height + beat * 0.07)
            let shimmer = 0.08 * sin(time * 2.4 + Float(index) * 0.41) * frame.trebleEnergy
            let color = mix(mix(palette.0, palette.1, position), palette.2, pow(position, 2.0) * 0.45)
            let topColor = SIMD4<Float>(
                min(1, color.x + 0.20 + shimmer),
                min(1, color.y + 0.14 + shimmer * 0.35),
                min(1, color.z + 0.24),
                0.88
            )
            let bottomColor = SIMD4<Float>(color.x * 0.30, color.y * 0.34, color.z * 0.42, 0.74)
            appendQuad(&vertices, x0: x0, y0: y0, x1: x1, y1: y1, bottom: bottomColor, top: topColor)

            let cap = 0.004 + energy * 0.006 + frame.trebleEnergy * 0.003
            appendQuad(
                &vertices,
                x0: x0 - 0.002,
                y0: y1,
                x1: x1 + 0.002,
                y1: min(0.94, y1 + cap),
                bottom: SIMD4<Float>(min(1, color.x + 0.20), min(1, color.y + 0.18), min(1, color.z + 0.26), 0.68),
                top: SIMD4<Float>(1, 1, 1, 0.26 + frame.trebleEnergy * 0.18)
            )

            let reflection = min(0.36, height * (0.18 + frame.smoothedVolume * 0.28))
            appendQuad(
                &vertices,
                x0: x0 + 0.001,
                y0: max(-0.98, y0 - reflection - 0.025),
                x1: x1 - 0.001,
                y1: y0 - 0.018,
                bottom: SIMD4<Float>(color.x, color.y, color.z, 0.01),
                top: SIMD4<Float>(color.x, color.y, color.z, 0.10 + beat * 0.08)
            )

            if frame.bassEnergy > 0.03 {
                let glow = min(0.22, frame.bassEnergy * 0.22 + beat * 0.16)
                appendQuad(
                    &vertices,
                    x0: x0 - 0.006,
                    y0: y0 - 0.02,
                    x1: x1 + 0.006,
                    y1: y1 + 0.035,
                    bottom: SIMD4<Float>(color.x, color.y, color.z, glow * 0.35),
                    top: SIMD4<Float>(color.x, color.y, color.z, glow)
                )
            }
        }
    }

    private func liquidWaveform(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let waveform = frame.waveform.isEmpty ? VisualAudioFrame.silent.waveform : frame.waveform
        let palette = paletteColors(settings.palette)
        let sensitivity = Float(settings.sensitivity)
        let intensity = Float(settings.intensity)
        let count = min(180, waveform.count)
        vertices.reserveCapacity(max(0, (count - 1) * 20) + 140)
        appendCinematicBackdrop(into: &vertices, frame: frame, settings: settings, time: time, palette: palette)

        for layer in 0..<3 {
            let layerDepth = Float(layer)
            let amplitude = sensitivity * (0.58 - layerDepth * 0.12)
            let thickness = (0.010 + frame.smoothedBass * 0.040 * intensity) * (1.0 + layerDepth * 0.62)
            let verticalOffset = (layerDepth - 1.0) * (0.034 + frame.midEnergy * 0.030)
            let phase = time * (0.55 + layerDepth * 0.16)
            let alphaBase = (0.66 - layerDepth * 0.18) + frame.smoothedVolume * 0.22

            for index in 0..<(count - 1) {
                let t0 = Float(index) / Float(count - 1)
                let t1 = Float(index + 1) / Float(count - 1)
                let x0 = -0.92 + t0 * 1.84
                let x1 = -0.92 + t1 * 1.84
                let wave0 = waveform[index] * amplitude
                let wave1 = waveform[index + 1] * amplitude
                let liquid0 = sin((t0 * 7.0) + phase) * frame.bassEnergy * 0.045
                    + sin((t0 * 18.0) - time * 0.32) * frame.trebleEnergy * 0.012
                let liquid1 = sin((t1 * 7.0) + phase) * frame.bassEnergy * 0.045
                    + sin((t1 * 18.0) - time * 0.32) * frame.trebleEnergy * 0.012
                let y0 = wave0 + liquid0 + verticalOffset
                let y1 = wave1 + liquid1 + verticalOffset
                let color = mix(mix(palette.0, palette.1, t0), palette.2, 0.35 + layerDepth * 0.18)
                let topColor = SIMD4<Float>(min(1, color.x + 0.10), min(1, color.y + 0.08), min(1, color.z + 0.14), alphaBase)
                let bottomColor = SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, alphaBase * (0.42 + layerDepth * 0.08))

                appendRibbonSegment(
                    &vertices,
                    x0: x0,
                    y0: y0,
                    x1: x1,
                    y1: y1,
                    halfThickness: thickness,
                    colorA: bottomColor,
                    colorB: topColor
                )
            }
        }

        let pulse = frame.beatPulse * 0.24
        appendQuad(
            &vertices,
            x0: -0.96,
            y0: -0.04 - pulse,
            x1: 0.96,
            y1: 0.04 + pulse,
            bottom: SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, 0.04 + pulse * 0.12),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.08 + pulse * 0.18)
        )
    }

    private func particleGalaxy(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let palette = paletteColors(settings.palette)
        let particleCount = 560
        let sensitivity = Float(settings.sensitivity)
        let intensity = Float(settings.intensity)
        let beat = frame.beatPulse * Float(settings.beatReactivity)
        let motion = settings.reduceMotion ? Float(0.18) : Float(settings.motionAmount)
        vertices.reserveCapacity(particleCount * 6 + 1_900)
        appendCinematicBackdrop(into: &vertices, frame: frame, settings: settings, time: time, palette: palette)

        for arm in 0..<3 {
            appendSpiralArm(
                into: &vertices,
                frame: frame,
                palette: palette,
                time: time,
                armOffset: Float(arm) * Float.pi * 2 / 3,
                motion: motion,
                intensity: intensity
            )
        }

        for index in 0..<particleCount {
            let seed = Float(index)
            let ring = fract(sin(seed * 12.9898) * 43_758.5453)
            let angleSeed = fract(sin(seed * 78.233) * 18_234.123)
            let radius = 0.06 + pow(ring, 0.58) * (0.82 + frame.bassEnergy * 0.32 + beat * 0.24)
            let angle = angleSeed * Float.pi * 2 + time * (0.035 + motion * 0.14) * (0.4 + ring)
            let spiral = frame.midEnergy * 0.30 * sin(time * 0.58 + seed * 0.13) + frame.highMidEnergy * 0.10
            let x = cos(angle + spiral) * radius
            let y = sin(angle + spiral) * radius * 0.78
            let shimmer = 0.26 + frame.trebleEnergy * sensitivity * fract(sin(seed * 91.7 + time * 3.6) * 111.1)
            let size = (0.0026 + ring * 0.0065 + beat * 0.006 + frame.onsetStrength * 0.003) * (0.72 + intensity)
            let color = mix(mix(palette.0, palette.1, ring), palette.2, pow(ring, 1.8))
            let alpha = min(0.90, 0.12 + shimmer * 0.52 + frame.smoothedVolume * 0.24)
            appendQuad(
                &vertices,
                x0: x - size,
                y0: y - size,
                x1: x + size,
                y1: y + size,
                bottom: SIMD4<Float>(color.x, color.y, color.z, alpha * 0.55),
                top: SIMD4<Float>(min(1, color.x + 0.2), min(1, color.y + 0.2), min(1, color.z + 0.2), alpha)
            )
        }

        appendEllipseRibbon(
            &vertices,
            radiusX: 0.28 + frame.midEnergy * 0.08,
            radiusY: 0.18 + frame.midEnergy * 0.05,
            rotation: time * (0.08 + motion * 0.18),
            segments: 96,
            halfThickness: 0.0025 + frame.trebleEnergy * 0.004,
            colorA: SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, 0.20 + frame.midEnergy * 0.16),
            colorB: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.12 + frame.trebleEnergy * 0.18)
        )

        let core = 0.06 + frame.smoothedBass * 0.24 + beat * 0.18
        appendQuad(
            &vertices,
            x0: -core,
            y0: -core,
            x1: core,
            y1: core,
            bottom: SIMD4<Float>(palette.1.x, palette.1.y, palette.1.z, 0.08),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.38 + beat * 0.18)
        )
    }

    private func neonTunnel(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let palette = paletteColors(settings.palette)
        let ringCount = 30
        let segmentCount = 88
        let beat = frame.beatPulse * Float(settings.beatReactivity)
        let motion = settings.reduceMotion ? Float(0.12) : Float(settings.motionAmount)
        vertices.reserveCapacity(ringCount * segmentCount * 6 + 260)
        appendCinematicBackdrop(into: &vertices, frame: frame, settings: settings, time: time, palette: palette)

        for ring in 0..<ringCount {
            let depth = Float(ring) / Float(ringCount)
            let radius = 0.06 + pow(depth, 1.32) * (1.18 + beat * 0.26 + frame.smoothedBass * 0.10)
            let twist = time * (0.18 + motion * 0.45) + depth * 3.65 + frame.smoothedBass * 0.38 + frame.midEnergy * 0.14
            let width = 0.0026 + (1 - depth) * 0.0055 + frame.trebleEnergy * 0.0045
            let color = mix(mix(palette.0, palette.1, depth), palette.2, pow(depth, 1.5) * 0.48)
            let alpha = (1 - depth) * 0.40 + frame.smoothedVolume * 0.18 + beat * 0.08

            for segment in stride(from: 0, to: segmentCount, by: 2) {
                let t0 = Float(segment) / Float(segmentCount) * Float.pi * 2
                let t1 = Float(segment + 1) / Float(segmentCount) * Float.pi * 2
                let x0 = cos(t0 + twist) * radius
                let y0 = sin(t0 + twist) * radius * 0.72
                let x1 = cos(t1 + twist) * radius
                let y1 = sin(t1 + twist) * radius * 0.72
                appendRibbonSegment(
                    &vertices,
                    x0: x0,
                    y0: y0,
                    x1: x1,
                    y1: y1,
                    halfThickness: width,
                    colorA: SIMD4<Float>(color.x, color.y, color.z, alpha),
                    colorB: SIMD4<Float>(min(1, color.x + 0.22), min(1, color.y + 0.16), min(1, color.z + 0.22), alpha * 0.72)
                )
            }
        }

        for ray in 0..<24 {
            let angle = Float(ray) / 24 * Float.pi * 2 + time * (0.08 + motion * 0.14)
            let inner = 0.08 + frame.smoothedBass * 0.05
            let outer = 1.24 + beat * 0.14
            let color = mix(palette.1, palette.2, Float(ray % 6) / 5)
            appendRibbonSegment(
                &vertices,
                x0: cos(angle) * inner,
                y0: sin(angle) * inner * 0.72,
                x1: cos(angle + frame.midEnergy * 0.08) * outer,
                y1: sin(angle + frame.midEnergy * 0.08) * outer * 0.72,
                halfThickness: 0.0016 + frame.trebleEnergy * 0.0018,
                colorA: SIMD4<Float>(color.x, color.y, color.z, 0.14 + beat * 0.10),
                colorB: SIMD4<Float>(color.x, color.y, color.z, 0.01)
            )
        }
    }

    private func minimalWaveform(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let waveform = frame.waveform.isEmpty ? VisualAudioFrame.silent.waveform : frame.waveform
        let palette = paletteColors(settings.palette)
        let count = min(150, waveform.count)
        let sensitivity = Float(settings.sensitivity) * 0.36
        let thickness: Float = 0.006 + frame.smoothedVolume * 0.012
        vertices.reserveCapacity(max(0, (count - 1) * 18) + 80)
        appendCinematicBackdrop(into: &vertices, frame: frame, settings: settings, time: time, palette: palette)

        appendQuad(
            &vertices,
            x0: -0.86,
            y0: -0.004,
            x1: 0.86,
            y1: 0.004,
            bottom: SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, 0.16),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.18)
        )

        for layer in 0..<2 {
            let offset = Float(layer) == 0 ? Float(0) : sin(time * 0.28) * frame.smoothedBass * 0.035
            let alpha = Float(layer) == 0 ? Float(0.62) : Float(0.24 + frame.midEnergy * 0.18)
            let layerThickness = thickness * (Float(layer) == 0 ? 1.0 : 1.9)
            for index in 0..<(count - 1) {
                let t0 = Float(index) / Float(count - 1)
                let t1 = Float(index + 1) / Float(count - 1)
                let x0 = -0.86 + t0 * 1.72
                let x1 = -0.86 + t1 * 1.72
                let drift0 = sin(time * 0.45 + t0 * 5.2) * frame.smoothedBass * 0.02
                let drift1 = sin(time * 0.45 + t1 * 5.2) * frame.smoothedBass * 0.02
                let y0 = waveform[index] * sensitivity + drift0 + offset
                let y1 = waveform[index + 1] * sensitivity + drift1 + offset
                let color = mix(palette.1, palette.2, t0)
                appendRibbonSegment(
                    &vertices,
                    x0: x0,
                    y0: y0,
                    x1: x1,
                    y1: y1,
                    halfThickness: layerThickness,
                    colorA: SIMD4<Float>(color.x, color.y, color.z, alpha * 0.72),
                    colorB: SIMD4<Float>(min(1, color.x + 0.12), min(1, color.y + 0.12), min(1, color.z + 0.12), alpha)
                )
            }
        }
    }

    private func fractalSurface(into vertices: inout [SpectraVertex], drawableSize: CGSize) {
        vertices.reserveCapacity(6)
        appendQuad(
            &vertices,
            x0: -1,
            y0: -1,
            x1: 1,
            y1: 1,
            bottom: SIMD4<Float>(1, 1, 1, 1),
            top: SIMD4<Float>(1, 1, 1, 1)
        )
    }

    private func makeFractalUniforms(
        preset: VisualPresetID,
        frame: VisualAudioFrame,
        settings: PresetSettings,
        time: Float,
        drawableSize: CGSize
    ) -> FractalUniforms {
        let mode = UInt32(max(0, preset.fullscreenShaderMode ?? 0))
        let motion = settings.reduceMotion ? Float(0.08) : Float(settings.motionAmount)
        return FractalUniforms(
            resolution: SIMD2<Float>(
                max(1, Float(drawableSize.width)),
                max(1, Float(drawableSize.height))
            ),
            time: time,
            rms: frame.rms,
            volume: frame.smoothedVolume,
            bass: frame.smoothedBass,
            mid: frame.midEnergy,
            treble: frame.trebleEnergy,
            beat: frame.beatPulse,
            intensity: Float(settings.intensity),
            sensitivity: Float(settings.sensitivity),
            motion: motion,
            glow: Float(settings.glowAmount),
            beatReactivity: Float(settings.beatReactivity),
            mode: mode,
            palette: paletteIndex(settings.palette)
        )
    }

    private func appendCinematicBackdrop(
        into vertices: inout [SpectraVertex],
        frame: VisualAudioFrame,
        settings: PresetSettings,
        time: Float,
        palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    ) {
        let motion = settings.reduceMotion ? Float(0.08) : Float(settings.motionAmount)
        let glow = Float(settings.glowAmount)
        let volume = min(1, frame.smoothedVolume * 1.15 + frame.midEnergy * 0.28)
        let bass = min(1, frame.smoothedBass * 1.18 + frame.subBassEnergy * 0.20)
        let treble = min(1, frame.trebleEnergy * 1.12)
        let beat = min(1, frame.beatPulse * Float(settings.beatReactivity))
        let drift = sin(time * (0.18 + motion * 0.20)) * 0.035 * motion
        let horizon = -0.34 + bass * 0.10 + drift

        appendQuad(
            &vertices,
            x0: -1,
            y0: -1,
            x1: 1,
            y1: 1,
            bottom: SIMD4<Float>(palette.0.x * 0.42, palette.0.y * 0.42, palette.0.z * 0.50, 0.08 + bass * 0.12 + beat * 0.06),
            top: SIMD4<Float>(palette.2.x * 0.26, palette.2.y * 0.24, palette.2.z * 0.32, 0.04 + volume * 0.10)
        )

        appendQuad(
            &vertices,
            x0: -1,
            y0: horizon - 0.13,
            x1: 1,
            y1: horizon + 0.13,
            bottom: SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, 0.04),
            top: SIMD4<Float>(palette.1.x, palette.1.y, palette.1.z, 0.16 + volume * 0.20 + glow * 0.06)
        )

        appendQuad(
            &vertices,
            x0: -1,
            y0: -1,
            x1: 1,
            y1: -0.64 + bass * 0.08,
            bottom: SIMD4<Float>(palette.1.x, palette.1.y, palette.1.z, 0.12 + bass * 0.16),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.02 + beat * 0.06)
        )

        let glintY = 0.58 + sin(time * 0.13) * 0.05
        appendRibbonSegment(
            &vertices,
            x0: -0.82,
            y0: glintY,
            x1: 0.82,
            y1: glintY + sin(time * 0.21) * 0.025,
            halfThickness: 0.0018 + treble * 0.004,
            colorA: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.04 + treble * 0.12),
            colorB: SIMD4<Float>(1, 1, 1, 0.04 + treble * 0.10)
        )
    }

    private func appendSpiralArm(
        into vertices: inout [SpectraVertex],
        frame: VisualAudioFrame,
        palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
        time: Float,
        armOffset: Float,
        motion: Float,
        intensity: Float
    ) {
        let segments = 96
        let beat = frame.beatPulse
        let bass = frame.smoothedBass
        let mid = frame.midEnergy
        let treble = frame.trebleEnergy
        for segment in 0..<segments {
            let t0 = Float(segment) / Float(segments)
            let t1 = Float(segment + 1) / Float(segments)
            let radius0 = 0.08 + pow(t0, 0.72) * (0.86 + bass * 0.28 + beat * 0.16)
            let radius1 = 0.08 + pow(t1, 0.72) * (0.86 + bass * 0.28 + beat * 0.16)
            let angle0 = armOffset + t0 * Float.pi * 3.4 + time * (0.035 + motion * 0.09) + mid * 0.28
            let angle1 = armOffset + t1 * Float.pi * 3.4 + time * (0.035 + motion * 0.09) + mid * 0.28
            let x0 = cos(angle0) * radius0
            let y0 = sin(angle0) * radius0 * 0.72
            let x1 = cos(angle1) * radius1
            let y1 = sin(angle1) * radius1 * 0.72
            let color = mix(palette.0, palette.2, t0)
            appendRibbonSegment(
                &vertices,
                x0: x0,
                y0: y0,
                x1: x1,
                y1: y1,
                halfThickness: (0.0022 + treble * 0.0045 + beat * 0.002) * (0.72 + intensity),
                colorA: SIMD4<Float>(color.x, color.y, color.z, 0.10 + (1 - t0) * 0.18),
                colorB: SIMD4<Float>(min(1, color.x + 0.18), min(1, color.y + 0.18), min(1, color.z + 0.18), 0.05 + (1 - t1) * 0.14)
            )
        }
    }

    private func appendEllipseRibbon(
        _ vertices: inout [SpectraVertex],
        radiusX: Float,
        radiusY: Float,
        rotation: Float,
        segments: Int,
        halfThickness: Float,
        colorA: SIMD4<Float>,
        colorB: SIMD4<Float>
    ) {
        guard segments > 2 else { return }
        for segment in 0..<segments {
            let t0 = Float(segment) / Float(segments) * Float.pi * 2
            let t1 = Float(segment + 1) / Float(segments) * Float.pi * 2
            let p0 = rotatePoint(SIMD2<Float>(cos(t0) * radiusX, sin(t0) * radiusY), rotation)
            let p1 = rotatePoint(SIMD2<Float>(cos(t1) * radiusX, sin(t1) * radiusY), rotation)
            let color = segment.isMultiple(of: 2) ? colorA : colorB
            appendRibbonSegment(
                &vertices,
                x0: p0.x,
                y0: p0.y,
                x1: p1.x,
                y1: p1.y,
                halfThickness: halfThickness,
                colorA: color,
                colorB: colorB
            )
        }
    }

    private func applyTraversalTransform(
        to vertices: inout [SpectraVertex],
        frame: VisualAudioFrame,
        settings: PresetSettings,
        time: Float
    ) {
        guard !vertices.isEmpty else { return }

        let motion = settings.reduceMotion ? Float(0.05) : Float(settings.motionAmount)
        let scale = 1
            + frame.smoothedBass * 0.018
            + frame.beatPulse * 0.012
            + frame.smoothedVolume * 0.006
        let rotation = sin(time * 0.18 + frame.midEnergy * 0.70) * 0.018 * motion
        let offset = SIMD2<Float>(
            sin(time * 0.13) * 0.020 * motion + sin(time * 0.41) * frame.highMidEnergy * 0.006,
            cos(time * 0.11) * 0.016 * motion + frame.smoothedBass * 0.008
        )

        for index in vertices.indices {
            let position = vertices[index].position * scale
            vertices[index].position = rotatePoint(position, rotation) + offset
        }
    }

    private func ensureVertexBuffer(device: MTLDevice, vertexCount: Int) -> MTLBuffer? {
        if vertexCount > vertexCapacity {
            vertexCapacity = max(vertexCount, vertexCapacity * 2, 1_024)
            vertexBuffer = device.makeBuffer(
                length: MemoryLayout<SpectraVertex>.stride * vertexCapacity,
                options: [.storageModeShared]
            )
        }
        return vertexBuffer
    }

    private func updateFPS() {
        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        guard now - fpsSampleStart >= 0.5 else { return }
        let fps = Double(fpsFrameCount) / (now - fpsSampleStart)
        fpsFrameCount = 0
        fpsSampleStart = now
        fpsHandler(fps)
    }

    private func backgroundColor(for palette: ColorPalette, frame: VisualAudioFrame) -> SIMD3<Float> {
        let energy = frame.smoothedVolume * 0.035 + frame.beatPulse * 0.018
        switch palette {
        case .aurora:
            return SIMD3<Float>(0.006 + energy, 0.010 + energy * 0.7, 0.018 + energy)
        case .magma:
            return SIMD3<Float>(0.020 + energy, 0.008 + energy * 0.4, 0.006 + energy * 0.2)
        case .prism:
            return SIMD3<Float>(0.010 + energy * 0.5, 0.010 + energy, 0.020 + energy)
        case .graphite:
            return SIMD3<Float>(0.010 + energy, 0.011 + energy, 0.012 + energy)
        }
    }

    private func paletteColors(_ palette: ColorPalette) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch palette {
        case .aurora:
            return (SIMD3<Float>(0.07, 0.85, 0.88), SIMD3<Float>(0.35, 0.96, 0.50), SIMD3<Float>(0.94, 0.30, 0.72))
        case .magma:
            return (SIMD3<Float>(0.98, 0.28, 0.18), SIMD3<Float>(1.00, 0.66, 0.20), SIMD3<Float>(0.56, 0.18, 0.94))
        case .prism:
            return (SIMD3<Float>(0.12, 0.42, 1.00), SIMD3<Float>(0.85, 0.22, 0.96), SIMD3<Float>(0.20, 1.00, 0.70))
        case .graphite:
            return (SIMD3<Float>(0.70, 0.78, 0.82), SIMD3<Float>(0.34, 0.54, 0.65), SIMD3<Float>(0.95, 0.96, 0.90))
        }
    }

    private func paletteIndex(_ palette: ColorPalette) -> UInt32 {
        switch palette {
        case .aurora: return 0
        case .magma: return 1
        case .prism: return 2
        case .graphite: return 3
        }
    }

    private func appendQuad(
        _ vertices: inout [SpectraVertex],
        x0: Float,
        y0: Float,
        x1: Float,
        y1: Float,
        bottom: SIMD4<Float>,
        top: SIMD4<Float>
    ) {
        vertices.append(SpectraVertex(position: SIMD2<Float>(x0, y0), color: bottom))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x1, y0), color: bottom))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x0, y1), color: top))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x1, y0), color: bottom))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x1, y1), color: top))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x0, y1), color: top))
    }

    private func appendRibbonSegment(
        _ vertices: inout [SpectraVertex],
        x0: Float,
        y0: Float,
        x1: Float,
        y1: Float,
        halfThickness: Float,
        colorA: SIMD4<Float>,
        colorB: SIMD4<Float>
    ) {
        let dx = x1 - x0
        let dy = y1 - y0
        let length = max(0.0001, sqrt(dx * dx + dy * dy))
        let nx = -dy / length * halfThickness
        let ny = dx / length * halfThickness

        vertices.append(SpectraVertex(position: SIMD2<Float>(x0 + nx, y0 + ny), color: colorA))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x0 - nx, y0 - ny), color: colorA))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x1 + nx, y1 + ny), color: colorB))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x0 - nx, y0 - ny), color: colorA))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x1 - nx, y1 - ny), color: colorB))
        vertices.append(SpectraVertex(position: SIMD2<Float>(x1 + nx, y1 + ny), color: colorB))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * min(1, max(0, t))
    }

    private func rotatePoint(_ value: SIMD2<Float>, _ angle: Float) -> SIMD2<Float> {
        let sine = sin(angle)
        let cosine = cos(angle)
        return SIMD2<Float>(
            value.x * cosine - value.y * sine,
            value.x * sine + value.y * cosine
        )
    }

    private func fract(_ value: Float) -> Float {
        value - floor(value)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SpectraVertex {
        float2 position;
        float4 color;
    };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    struct FractalUniforms {
        float2 resolution;
        float time;
        float rms;
        float volume;
        float bass;
        float mid;
        float treble;
        float beat;
        float intensity;
        float sensitivity;
        float motion;
        float glow;
        float beatReactivity;
        uint mode;
        uint palette;
    };

    vertex VertexOut spectra_vertex(uint vertexID [[vertex_id]],
                                    constant SpectraVertex *vertices [[buffer(0)]]) {
        VertexOut out;
        SpectraVertex inputVertex = vertices[vertexID];
        out.position = float4(inputVertex.position, 0.0, 1.0);
        out.color = inputVertex.color;
        return out;
    }

    fragment half4 spectra_fragment(VertexOut input [[stage_in]]) {
        return half4(input.color);
    }

    float2 rotate2(float2 value, float angle) {
        float s = sin(angle);
        float c = cos(angle);
        return float2(value.x * c - value.y * s, value.x * s + value.y * c);
    }

    float2 complexSquare(float2 value) {
        return float2(value.x * value.x - value.y * value.y, 2.0 * value.x * value.y);
    }

    float3 lerp3(float3 a, float3 b, float t) {
        return a + (b - a) * clamp(t, 0.0, 1.0);
    }

    float3 paletteGradient(uint palette, float t) {
        t = fract(t);
        if (palette == 0) {
            float3 a = float3(0.04, 0.78, 0.94);
            float3 b = float3(0.28, 0.98, 0.46);
            float3 c = float3(0.98, 0.25, 0.72);
            return t < 0.5 ? lerp3(a, b, t * 2.0) : lerp3(b, c, (t - 0.5) * 2.0);
        }
        if (palette == 1) {
            float3 a = float3(0.92, 0.16, 0.10);
            float3 b = float3(1.00, 0.58, 0.12);
            float3 c = float3(0.52, 0.12, 0.92);
            return t < 0.56 ? lerp3(a, b, t / 0.56) : lerp3(b, c, (t - 0.56) / 0.44);
        }
        if (palette == 2) {
            return 0.55 + 0.45 * cos(6.2831853 * (float3(t, t + 0.34, t + 0.68)));
        }
        float3 low = float3(0.10, 0.13, 0.14);
        float3 high = float3(0.90, 0.94, 0.90);
        return lerp3(low, high, smoothstep(0.08, 0.92, t));
    }

    float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float spectralFilament(float2 point, constant FractalUniforms &u) {
        float radius = length(point);
        float angle = atan2(point.y, point.x);
        float tempo = u.time * (0.16 + u.motion * 0.42);
        float bassFold = sin(radius * (8.0 + u.bass * 8.0) - tempo * 3.2 + u.beat * 1.8);
        float midFold = sin(angle * (3.0 + u.mid * 4.0) + radius * 15.0 + tempo * 2.1);
        float trebleFold = sin(radius * 42.0 - angle * 5.0 + tempo * 5.8);
        float filament = bassFold * 0.46 + midFold * 0.36 + trebleFold * u.treble * 0.28;
        return smoothstep(0.72, 1.0, filament) * smoothstep(1.70, 0.18, radius);
    }

    float transientDust(float2 point, constant FractalUniforms &u) {
        float2 cell = floor((point + 1.6) * (70.0 + u.treble * 42.0));
        float seed = hash21(cell + floor(u.time * (0.8 + u.motion * 1.8)));
        float threshold = 0.992 - clamp(u.treble * 0.014 + u.beat * 0.010, 0.0, 0.025);
        float sparkle = smoothstep(threshold, 1.0, seed);
        return sparkle * smoothstep(0.12, 1.45, length(point)) * (0.08 + u.treble * 0.36 + u.beat * 0.28);
    }

    float terrainHeight(float2 p, constant FractalUniforms &u) {
        float height = 0.0;
        float amplitude = 0.46;
        float frequency = 0.42;
        for (int octave = 0; octave < 6; octave++) {
            float wave = sin(p.x * frequency + u.time * 0.13 + u.mid * 1.8)
                * cos(p.y * frequency * 0.82 - u.time * 0.10 + u.bass * 2.2);
            float cell = hash21(floor(p * frequency * 1.7));
            height += (wave * 0.74 + (cell - 0.5) * 0.52) * amplitude;
            amplitude *= 0.50;
            frequency *= 2.03;
        }
        return height * (0.30 + u.intensity * 0.34) + u.bass * 0.12;
    }

    float4 terrainFlight(float2 point, constant FractalUniforms &u) {
        float speed = 1.20 + u.motion * 3.0 + u.volume * 0.85 + u.beat * 0.70;
        float travel = u.time * speed;
        float3 camera = float3(sin(travel * 0.10) * 1.3, 0.58 + u.volume * 0.36 + u.bass * 0.20, travel);
        float3 ray = normalize(float3(point.x * 0.92, point.y * 0.62 - 0.10 + u.mid * 0.08, 1.34));
        ray.xz = rotate2(ray.xz, sin(travel * 0.07) * 0.18 + u.mid * 0.08);

        float3 color = paletteGradient(u.palette, 0.60 + point.y * 0.12) * (0.10 + u.volume * 0.10);
        float closest = 10.0;
        float hitAmount = 0.0;
        float t = 0.08;
        for (int i = 0; i < 64; i++) {
            float3 pos = camera + ray * t;
            float height = terrainHeight(pos.xz, u);
            float distanceToGround = pos.y - height;
            closest = min(closest, abs(distanceToGround));
            if (distanceToGround < 0.018) {
                float eps = 0.035;
                float hx = terrainHeight(pos.xz + float2(eps, 0.0), u) - terrainHeight(pos.xz - float2(eps, 0.0), u);
                float hz = terrainHeight(pos.xz + float2(0.0, eps), u) - terrainHeight(pos.xz - float2(0.0, eps), u);
                float3 normal = normalize(float3(-hx, 0.08, -hz));
                float light = clamp(dot(normal, normalize(float3(-0.42, 0.74, -0.48))), 0.0, 1.0);
                float fog = exp(-t * (0.18 - u.glow * 0.05));
                float ridge = smoothstep(0.45, 1.0, light) + u.treble * 0.22 + u.beat * 0.18;
                color = paletteGradient(u.palette, 0.18 + height * 0.22 + t * 0.025)
                    * (0.20 + light * 0.76 + ridge * 0.20)
                    * fog;
                hitAmount = 1.0;
                break;
            }
            t += max(0.035, abs(distanceToGround) * 0.32 + t * 0.018);
        }

        float horizon = smoothstep(-0.12, 0.52, point.y + u.volume * 0.12);
        float glow = exp(-closest * (4.0 + u.glow * 6.0)) * (0.12 + u.bass * 0.30 + u.beat * 0.24);
        color += paletteGradient(u.palette, 0.78 + u.time * 0.05) * horizon * (0.08 + u.glow * 0.18);
        color += paletteGradient(u.palette, 0.32 + u.treble * 0.20) * glow;
        color += transientDust(point * 0.82, u) * paletteGradient(u.palette, 0.92);
        color *= 0.78 + hitAmount * 0.42;
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }

    float mandelboxDensity(float3 p, constant FractalUniforms &u) {
        float3 z = p;
        float scale = -1.72 - u.bass * 0.22 + u.beat * 0.10;
        float orbit = 10.0;
        for (int i = 0; i < 9; i++) {
            z = clamp(z, -1.0, 1.0) * 2.0 - z;
            float r2 = dot(z, z);
            if (r2 < 0.35) {
                z *= 2.86;
            } else if (r2 < 1.0) {
                z /= r2;
            }
            z = z * scale + p;
            orbit = min(orbit, abs(length(z) - 1.0));
        }
        return exp(-orbit * (3.0 + u.glow * 5.0));
    }

    float4 mandelboxFlight(float2 point, constant FractalUniforms &u) {
        float travel = u.time * (0.65 + u.motion * 1.8 + u.volume * 0.70 + u.beat * 0.60);
        float3 ray = normalize(float3(point.x * 0.82, point.y * 0.72, 1.12));
        ray.xy = rotate2(ray.xy, sin(travel * 0.18) * 0.22 + u.mid * 0.16);
        float3 origin = float3(sin(travel * 0.21) * 0.35, cos(travel * 0.17) * 0.26, travel);

        float3 color = float3(0.0);
        float transmittance = 1.0;
        for (int i = 0; i < 54; i++) {
            float depth = float(i) * 0.060;
            float3 pos = origin + ray * depth;
            pos.xy = rotate2(pos.xy, depth * 0.18 + u.mid * 0.26);
            pos.z = fract(pos.z * 0.18) * 5.6 - 2.8;
            float density = mandelboxDensity(pos, u) * (0.055 + u.intensity * 0.055);
            float phase = depth * 0.10 + density * 1.6 + u.time * 0.05 + u.treble * 0.25;
            color += paletteGradient(u.palette, phase) * density * transmittance * (1.1 + u.beat * 0.7);
            transmittance *= 1.0 - density * 0.42;
            if (transmittance < 0.05) {
                break;
            }
        }

        float edge = spectralFilament(point * (1.0 + u.bass * 0.25), u);
        color += paletteGradient(u.palette, 0.65 + u.time * 0.07) * edge * (0.12 + u.glow * 0.20);
        color += paletteGradient(u.palette, 0.95) * transientDust(point, u) * 0.65;
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }

    float4 nebulaVoyage(float2 point, constant FractalUniforms &u) {
        float radius = length(point);
        float angle = atan2(point.y, point.x);
        float speed = u.time * (0.55 + u.motion * 1.9 + u.volume * 0.65 + u.beat * 0.75);
        float3 color = float3(0.0);
        float fade = smoothstep(1.65, 0.08, radius);

        for (int layer = 0; layer < 7; layer++) {
            float lf = float(layer);
            float z = speed + lf * 0.72;
            float tunnel = sin(angle * (2.0 + lf * 0.45 + u.mid * 1.4) + z * 1.7)
                + cos(radius * (9.0 + lf * 2.4 + u.bass * 4.0) - z * 1.15);
            float band = smoothstep(0.35, 1.0, tunnel * 0.5 + 0.5);
            float depth = 1.0 / (1.0 + lf * 0.42 + radius * 0.65);
            color += paletteGradient(u.palette, lf * 0.12 + z * 0.06 + u.treble * 0.18)
                * band * depth * (0.055 + u.glow * 0.040 + u.volume * 0.032);
        }

        float core = exp(-abs(radius - (0.42 + u.bass * 0.10 + sin(speed * 0.5) * 0.04)) * (7.0 + u.glow * 7.0));
        float stars = transientDust(point * (1.4 + u.treble * 0.6), u);
        color += paletteGradient(u.palette, 0.22 + speed * 0.06) * core * (0.15 + u.beat * 0.20);
        color += paletteGradient(u.palette, 0.84 + u.treble * 0.18) * stars * 0.85;
        color *= fade * (0.90 + u.intensity * 0.35);
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }

    float4 iterateFractal(float2 point, constant FractalUniforms &u) {
        if (u.mode == 5) {
            return mandelboxFlight(point, u);
        }
        if (u.mode == 6) {
            return terrainFlight(point, u);
        }
        if (u.mode == 7) {
            return nebulaVoyage(point, u);
        }

        float audio = clamp(max(u.volume, sqrt(max(u.rms, 0.0)) * 0.70) * (0.78 + u.sensitivity), 0.0, 1.0);
        float bass = clamp(u.bass * (0.78 + u.sensitivity), 0.0, 1.2);
        float mid = clamp(u.mid * (0.78 + u.sensitivity), 0.0, 1.2);
        float treble = clamp(u.treble * (0.78 + u.sensitivity), 0.0, 1.2);
        float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
        float travel = u.time * (0.018 + u.motion * 0.090);
        float rotateAmount = sin(travel * 0.73 + mid * 1.7) * (0.10 + u.motion * 0.42);
        float zoom = 1.0 + bass * 0.28 + beat * 0.20 + audio * 0.14;
        float2 p = rotate2(point, rotateAmount) / zoom;
        float warp = (mid * 0.034 + treble * 0.022 + beat * 0.018) * (0.36 + u.motion);
        p += float2(
            sin(p.y * 4.2 + travel * 4.8 + bass),
            cos(p.x * 3.6 - travel * 4.0 + mid)
        ) * warp;
        float2 z = float2(0.0);
        float2 c = p;
        float2 previous = float2(0.0);
        float2 phoenix = float2(-0.52 + bass * 0.18, 0.03 + beat * 0.18);

        if (u.mode == 0) {
            c = p * 1.58 + float2(-0.56 + sin(travel) * 0.035 + bass * 0.050, mid * 0.055);
            z = float2(0.0);
        } else if (u.mode == 1) {
            z = p * (1.36 - beat * 0.12);
            c = float2(
                -0.74 + sin(travel * 1.3) * 0.12 + bass * 0.09,
                0.22 + cos(travel * 0.9) * 0.20 + mid * 0.10
            );
        } else if (u.mode == 2) {
            c = p * 1.72 + float2(-0.48 + bass * 0.08, -0.45 + sin(travel) * 0.08);
            z = float2(0.0);
        } else if (u.mode == 3) {
            c = p * 1.66 + float2(-0.22 + sin(travel * 0.8) * 0.05, cos(travel * 0.7) * 0.05 + mid * 0.06);
            z = float2(0.0);
        } else {
            z = p * 1.38;
            c = float2(-0.42 + treble * 0.12 + sin(travel) * 0.04, 0.08 + mid * 0.10);
            previous = float2(0.0);
        }

        int maxIterations = 50 + int(clamp(u.intensity, 0.0, 1.0) * 38.0 + treble * 12.0);
        float minOrbit = 32.0;
        int iteration = 0;
        for (int i = 0; i < 104; i++) {
            if (i >= maxIterations) {
                break;
            }

            if (u.mode == 2) {
                z = abs(z);
                z = complexSquare(z) + c;
            } else if (u.mode == 3) {
                z = float2(z.x, -z.y);
                z = complexSquare(z) + c;
            } else if (u.mode == 4) {
                float2 next = complexSquare(z) + c + phoenix * previous;
                previous = z;
                z = next;
            } else {
                z = complexSquare(z) + c;
            }

            float orbit = dot(z, z);
            minOrbit = min(minOrbit, orbit);
            iteration = i;
            if (orbit > 16.0) {
                break;
            }
        }

        float escaped = dot(z, z) > 16.0 ? 1.0 : 0.0;
        float normalized = float(iteration) / float(maxIterations);
        float orbitGlow = exp(-minOrbit * (2.2 + u.glow * 4.8));
        float edge = escaped > 0.5 ? pow(1.0 - normalized, 0.72) : orbitGlow;
        float colorPhase = normalized * (1.8 + u.intensity * 2.4)
            + travel * (0.42 + u.motion)
            + treble * 0.55
            + beat * 0.18;
        float3 color = paletteGradient(u.palette, colorPhase);
        float contour = 0.5 + 0.5 * sin((normalized * 68.0) + travel * 18.0 + treble * 6.0);
        float brightness = 0.08
            + edge * (0.54 + u.glow * 0.42)
            + orbitGlow * (0.20 + bass * 0.30)
            + contour * treble * 0.13
            + beat * 0.10;
        float vignette = smoothstep(1.55, 0.20, length(point));
        color *= brightness * (0.55 + vignette * 0.62);
        color += paletteGradient(u.palette, colorPhase + 0.21) * orbitGlow * (0.10 + u.glow * 0.30);
        float filament = spectralFilament(point, u);
        color += paletteGradient(u.palette, colorPhase + 0.38) * filament * (0.09 + treble * 0.18 + u.glow * 0.08);
        color += paletteGradient(u.palette, colorPhase + 0.62) * transientDust(point, u);
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }

    fragment half4 spectra_fractal_fragment(VertexOut input [[stage_in]],
                                            constant FractalUniforms &uniforms [[buffer(0)]]) {
        float2 size = max(uniforms.resolution, float2(1.0));
        float2 uv = input.position.xy / size;
        float2 point = (uv - 0.5) * 2.0;
        point.x *= size.x / size.y;
        return half4(iterateFractal(point, uniforms));
    }
    """
}
