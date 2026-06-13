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

private struct TerrainVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct TerrainUniforms {
    var viewProjectionMatrix: simd_float4x4
    var cameraPosition: SIMD4<Float>
    var lightDirection: SIMD4<Float>
    var fogColor: SIMD4<Float>
    var audio: SIMD4<Float>
    var fogStart: Float
    var fogEnd: Float
    var time: Float
    var palette: UInt32
}

private struct RenderSignalState {
    private var volume = AttackReleaseEnvelope(initialValue: 0, attack: 0.52, release: 0.975)
    private var bass = AttackReleaseEnvelope(initialValue: 0, attack: 0.48, release: 0.982)
    private var mid = AttackReleaseEnvelope(initialValue: 0, attack: 0.56, release: 0.970)
    private var highMid = AttackReleaseEnvelope(initialValue: 0, attack: 0.58, release: 0.960)
    private var treble = AttackReleaseEnvelope(initialValue: 0, attack: 0.62, release: 0.945)
    private var beat = AttackReleaseEnvelope(initialValue: 0, attack: 0.34, release: 0.900)
    private var onset = AttackReleaseEnvelope(initialValue: 0, attack: 0.42, release: 0.920)
    private var spectrumSmoother = SpectrumSmoother(count: 96, attack: 0.58, release: 0.940)
    private(set) var visualTime: Float = 0

    mutating func process(
        _ frame: VisualAudioFrame,
        settings: PresetSettings,
        deltaTime: TimeInterval
    ) -> VisualAudioFrame {
        let motion = settings.reduceMotion ? Float(0.08) : Float(settings.motionAmount)
        let smoothing = Float(settings.smoothing)
        let sensitivityGain = 0.48 + Float(settings.sensitivity) * 0.62
        let beatGain = 0.46 + Float(settings.beatReactivity) * 0.46
        let easedDelta = deltaTime * Double(0.80 + smoothing * 0.55)

        let volumeInput = shapeEnergy(max(frame.smoothedVolume, frame.rms * 1.18), gain: sensitivityGain, floor: 0.020, power: 1.22, ceiling: 0.86)
        let bassInput = shapeEnergy(max(frame.smoothedBass, frame.bassEnergy), gain: sensitivityGain * 0.92, floor: 0.026, power: 1.24, ceiling: 0.84)
        let midInput = shapeEnergy(frame.midEnergy, gain: sensitivityGain * 0.82, floor: 0.022, power: 1.28, ceiling: 0.78)
        let highMidInput = shapeEnergy(frame.highMidEnergy, gain: sensitivityGain * 0.78, floor: 0.024, power: 1.32, ceiling: 0.74)
        let trebleInput = shapeEnergy(max(frame.smoothedTreble, frame.trebleEnergy), gain: sensitivityGain * 0.86, floor: 0.030, power: 1.36, ceiling: 0.72)
        let beatInput = shapeEnergy(frame.beatPulse * 0.70 + frame.onsetStrength * 0.22, gain: beatGain, floor: 0.040, power: 1.50, ceiling: 0.58)
        let onsetInput = shapeEnergy(frame.onsetStrength, gain: beatGain * 0.74, floor: 0.045, power: 1.55, ceiling: 0.50)

        let smoothedVolume = volume.process(volumeInput, deltaTime: easedDelta)
        let smoothedBass = bass.process(bassInput, deltaTime: easedDelta)
        let smoothedMid = mid.process(midInput, deltaTime: easedDelta)
        let smoothedHighMid = highMid.process(highMidInput, deltaTime: easedDelta)
        let smoothedTreble = treble.process(trebleInput, deltaTime: easedDelta)
        let beatTrail = beat.process(beatInput, deltaTime: easedDelta)
        let onsetTrail = onset.process(onsetInput, deltaTime: easedDelta)
        let shapedSpectrum = frame.spectrumBands.map {
            shapeEnergy($0, gain: sensitivityGain * 0.92, floor: 0.018, power: 1.20, ceiling: 0.86)
        }
        let smoothedSpectrum = spectrumSmoother.process(shapedSpectrum, deltaTime: easedDelta)

        visualTime += Float(deltaTime) * (
            0.30
            + motion * 0.22
            + smoothedVolume * 0.11
            + smoothedBass * 0.08
            + beatTrail * 0.08
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
        output.spectrumBands = smoothedSpectrum
        return output
    }

    private func shapeEnergy(_ input: Float, gain: Float, floor: Float, power: Float, ceiling: Float) -> Float {
        let cleaned = max(0, input - floor) / max(0.001, 1 - floor)
        let scaled = min(1, cleaned * gain)
        let shaped = pow(scaled, power)
        return min(ceiling, shaped)
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
    private var terrainPipelineState: MTLRenderPipelineState?
    private var terrainDepthState: MTLDepthStencilState?
    private var startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()
    private var fpsSampleStart = CACurrentMediaTime()
    private var fpsFrameCount = 0
    private var renderSignalState = RenderSignalState()
    private var reusableVertices: [SpectraVertex] = []
    private var reusableTerrainVertices: [TerrainVertex] = []
    private var vertexBuffer: MTLBuffer?
    private var vertexCapacity = 0
    private var terrainVertexBuffer: MTLBuffer?
    private var terrainVertexCapacity = 0

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
        view.depthStencilPixelFormat = .depth32Float
        view.clearDepth = 1.0
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        if let library = makeShaderLibrary(for: view) {
            self.geometryPipelineState = makePipeline(for: view, library: library, fragmentFunctionName: "spectra_fragment")
            self.fractalPipelineState = makePipeline(for: view, library: library, fragmentFunctionName: "spectra_fractal_fragment")
            self.terrainPipelineState = makeTerrainPipeline(for: view, library: library)
            self.terrainDepthState = makeTerrainDepthState(device: device)
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
        let usesWorldRenderer = usesMeshWorldRenderer(preset)
        let usesFullscreenShader = preset.usesFullscreenShader && !usesWorldRenderer
        reusableVertices.removeAll(keepingCapacity: true)
        reusableTerrainVertices.removeAll(keepingCapacity: true)
        let terrainUniforms: TerrainUniforms?
        if usesWorldRenderer {
            terrainUniforms = makeMeshWorld(
                into: &reusableTerrainVertices,
                preset: preset,
                frame: frame,
                settings: settings,
                time: time,
                drawableSize: view.drawableSize
            )
            appendMeshWorldBackdrop(
                into: &reusableVertices,
                preset: preset,
                frame: frame,
                settings: settings,
                time: time
            )
        } else {
            terrainUniforms = nil
            appendVertices(
                into: &reusableVertices,
                for: preset,
                frame: frame,
                settings: settings,
                time: time,
                drawableSize: view.drawableSize
            )
        }
        if !usesFullscreenShader && !usesWorldRenderer {
            applyTraversalTransform(to: &reusableVertices, frame: frame, settings: settings, time: time)
        }
        if usesFullscreenShader, fractalPipelineState == nil {
            return
        }
        if !usesFullscreenShader, geometryPipelineState == nil {
            return
        }
        if usesWorldRenderer, terrainPipelineState == nil {
            return
        }

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

        if usesFullscreenShader {
            guard let fractalPipelineState else { return }
            encoder.setRenderPipelineState(fractalPipelineState)
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
            if usesFullscreenShader {
                guard let fractalPipelineState else { return }
                encoder.setRenderPipelineState(fractalPipelineState)
            } else {
                guard let geometryPipelineState else { return }
                encoder.setRenderPipelineState(geometryPipelineState)
            }
            let byteCount = MemoryLayout<SpectraVertex>.stride * reusableVertices.count
            reusableVertices.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
                }
            }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: reusableVertices.count)
        }
        if usesWorldRenderer,
           let terrainPipelineState,
           let terrainDepthState,
           var terrainUniforms,
           !reusableTerrainVertices.isEmpty,
           let buffer = ensureTerrainVertexBuffer(device: device, vertexCount: reusableTerrainVertices.count) {
            encoder.setRenderPipelineState(terrainPipelineState)
            encoder.setDepthStencilState(terrainDepthState)
            let byteCount = MemoryLayout<TerrainVertex>.stride * reusableTerrainVertices.count
            reusableTerrainVertices.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
                }
            }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&terrainUniforms, length: MemoryLayout<TerrainUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&terrainUniforms, length: MemoryLayout<TerrainUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: reusableTerrainVertices.count)
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

    private func makeTerrainPipeline(for view: MTKView, library: MTLLibrary) -> MTLRenderPipelineState? {
        guard let device = view.device else { return nil }
        guard let vertexFunction = library.makeFunction(name: "terrain_vertex"),
              let fragmentFunction = library.makeFunction(name: "terrain_fragment") else {
            assertionFailure("Spectra Metal shader library is missing terrain mesh functions.")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("Spectra Metal terrain pipeline creation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeTerrainDepthState(device: MTLDevice?) -> MTLDepthStencilState? {
        guard let device else { return nil }
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)
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
        case .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse, .phoenixField, .mandelboxFlight, .terrainFlight, .nebulaVoyage, .skyRealmFlight, .crystalCavern:
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

    private func usesMeshWorldRenderer(_ preset: VisualPresetID) -> Bool {
        preset.usesMeshWorld
    }

    private func appendMeshWorldBackdrop(
        into vertices: inout [SpectraVertex],
        preset: VisualPresetID,
        frame: VisualAudioFrame,
        settings: PresetSettings,
        time: Float
    ) {
        let palette = paletteColors(settings.palette)
        let glow = Float(settings.glowAmount)
        let volume = frame.smoothedVolume
        let sunX = preset == .skyRealmFlight ? Float(0.46) : Float(0.58)
        let sunY = preset == .skyRealmFlight ? Float(0.42) : Float(0.30)
        let skyLow = mix(palette.0 * 0.23, palette.1 * 0.20, 0.35 + volume * 0.18)
        let skyHigh = mix(palette.2 * 0.11, SIMD3<Float>(0.010, 0.018, 0.040), 0.45)
        let horizon = mix(palette.0 * 0.32, palette.2 * 0.18, 0.35)

        appendQuad(
            &vertices,
            x0: -1,
            y0: -1,
            x1: 1,
            y1: 1,
            bottom: SIMD4<Float>(skyLow.x, skyLow.y, skyLow.z, 1),
            top: SIMD4<Float>(skyHigh.x, skyHigh.y, skyHigh.z, 1)
        )

        appendQuad(
            &vertices,
            x0: -1,
            y0: -0.42,
            x1: 1,
            y1: 0.22,
            bottom: SIMD4<Float>(horizon.x, horizon.y, horizon.z, 0.18 + glow * 0.12),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.04 + volume * 0.06)
        )

        for layer in 0..<5 {
            let lf = Float(layer)
            let y = 0.02 + lf * 0.12 + sin(time * (0.06 + lf * 0.012) + lf) * 0.025
            let alpha = 0.028 + glow * 0.018 + frame.trebleEnergy * 0.015
            appendRibbonSegment(
                &vertices,
                x0: -1.05,
                y0: y,
                x1: 1.05,
                y1: y + sin(time * 0.05 + lf * 1.7) * 0.035,
                halfThickness: 0.018 + lf * 0.006,
                colorA: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, alpha),
                colorB: SIMD4<Float>(1, 1, 1, alpha * 0.35)
            )
        }

        let sunSize = 0.16 + glow * 0.09
        appendQuad(
            &vertices,
            x0: sunX - sunSize,
            y0: sunY - sunSize,
            x1: sunX + sunSize,
            y1: sunY + sunSize,
            bottom: SIMD4<Float>(palette.1.x, palette.1.y, palette.1.z, 0.06 + glow * 0.04),
            top: SIMD4<Float>(1, 0.94, 0.72, 0.16 + glow * 0.08)
        )
    }

    private func makeMeshWorld(
        into vertices: inout [TerrainVertex],
        preset: VisualPresetID,
        frame: VisualAudioFrame,
        settings: PresetSettings,
        time: Float,
        drawableSize: CGSize
    ) -> TerrainUniforms {
        let palette = paletteColors(settings.palette)
        let motion = settings.reduceMotion ? Float(0.12) : Float(settings.motionAmount)
        let intensity = Float(settings.intensity)
        let isSkyRealm = preset == .skyRealmFlight
        let travel = time * (9.0 + motion * 11.0 + frame.smoothedVolume * 1.5)
        let cameraX = sin(time * 0.31) * (isSkyRealm ? 6.8 : 4.4) + sin(time * 0.093) * (isSkyRealm ? 7.0 : 3.2)
        let cameraY = (isSkyRealm ? Float(6.2) : Float(3.0)) + frame.smoothedVolume * 0.85 + frame.smoothedBass * 0.35
        let camera = SIMD3<Float>(cameraX, cameraY, travel)
        let target = SIMD3<Float>(
            cameraX + sin(time * 0.23) * (isSkyRealm ? 5.5 : 3.0),
            isSkyRealm ? 2.2 + frame.midEnergy * 0.70 : 1.05 + frame.midEnergy * 0.45,
            travel + (isSkyRealm ? 19.0 : 16.0)
        )
        let aspect = max(0.2, Float(drawableSize.width / max(1, drawableSize.height)))
        let projection = perspectiveMatrix(fovY: Float.pi / 3.05, aspect: aspect, near: 0.08, far: 125)
        let view = lookAtMatrix(eye: camera, center: target, up: SIMD3<Float>(0, 1, 0))
        let viewProjection = simd_mul(projection, view)

        let columns = settings.reduceMotion ? 48 : 64
        let rows = settings.reduceMotion ? 72 : 92
        let worldWidth = isSkyRealm ? Float(58) : Float(48)
        let worldDepth = isSkyRealm ? Float(95) : Float(88)
        let stepX = worldWidth / Float(columns)
        let stepZ = worldDepth / Float(rows)
        let startX = camera.x - worldWidth * 0.5
        let startZ = camera.z + 1.8
        let pointColumns = columns + 1
        let pointRows = rows + 1
        let pointCount = pointColumns * pointRows
        var positions = Array(repeating: SIMD3<Float>(repeating: 0), count: pointCount)
        var heights = Array(repeating: Float(0), count: pointCount)
        var colors = Array(repeating: SIMD4<Float>(repeating: 1), count: pointCount)

        for row in 0..<pointRows {
            let z = startZ + Float(row) * stepZ
            for column in 0..<pointColumns {
                let x = startX + Float(column) * stepX
                let index = row * pointColumns + column
                let height = terrainHeight(
                    x: x,
                    z: z,
                    time: time,
                    frame: frame,
                    intensity: intensity,
                    isSkyRealm: isSkyRealm
                )
                heights[index] = height
                positions[index] = SIMD3<Float>(x, height, z)
            }
        }

        var normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: pointCount)
        for row in 0..<pointRows {
            for column in 0..<pointColumns {
                let index = row * pointColumns + column
                let left = heights[row * pointColumns + max(0, column - 1)]
                let right = heights[row * pointColumns + min(columns, column + 1)]
                let back = heights[max(0, row - 1) * pointColumns + column]
                let forward = heights[min(rows, row + 1) * pointColumns + column]
                let normal = simd_normalize(SIMD3<Float>(
                    -(right - left) / max(0.001, stepX * 2),
                    1.45,
                    -(forward - back) / max(0.001, stepZ * 2)
                ))
                normals[index] = normal
                colors[index] = terrainColor(
                    position: positions[index],
                    normal: normal,
                    frame: frame,
                    palette: palette,
                    time: time,
                    isSkyRealm: isSkyRealm
                )
            }
        }

        vertices.reserveCapacity(columns * rows * 6)
        for row in 0..<rows {
            for column in 0..<columns {
                let i00 = row * pointColumns + column
                let i10 = row * pointColumns + column + 1
                let i01 = (row + 1) * pointColumns + column
                let i11 = (row + 1) * pointColumns + column + 1
                appendTerrainVertex(&vertices, position: positions[i00], normal: normals[i00], color: colors[i00])
                appendTerrainVertex(&vertices, position: positions[i10], normal: normals[i10], color: colors[i10])
                appendTerrainVertex(&vertices, position: positions[i01], normal: normals[i01], color: colors[i01])
                appendTerrainVertex(&vertices, position: positions[i10], normal: normals[i10], color: colors[i10])
                appendTerrainVertex(&vertices, position: positions[i11], normal: normals[i11], color: colors[i11])
                appendTerrainVertex(&vertices, position: positions[i01], normal: normals[i01], color: colors[i01])
            }
        }

        let fogBase = isSkyRealm
            ? mix(SIMD3<Float>(0.05, 0.11, 0.16), palette.2 * 0.20, 0.45)
            : mix(SIMD3<Float>(0.025, 0.040, 0.060), palette.0 * 0.18, 0.42)
        let light = simd_normalize(SIMD3<Float>(
            isSkyRealm ? -0.36 : -0.54,
            isSkyRealm ? 0.78 : 0.84,
            isSkyRealm ? -0.28 : -0.34
        ))
        return TerrainUniforms(
            viewProjectionMatrix: viewProjection,
            cameraPosition: SIMD4<Float>(camera.x, camera.y, camera.z, 1),
            lightDirection: SIMD4<Float>(light.x, light.y, light.z, 0),
            fogColor: SIMD4<Float>(fogBase.x, fogBase.y, fogBase.z, 1),
            audio: SIMD4<Float>(frame.smoothedVolume, frame.smoothedBass, frame.trebleEnergy, frame.beatPulse),
            fogStart: isSkyRealm ? 18 : 16,
            fogEnd: isSkyRealm ? 92 : 78,
            time: time,
            palette: paletteIndex(settings.palette)
        )
    }

    private func appendTerrainVertex(
        _ vertices: inout [TerrainVertex],
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        color: SIMD4<Float>
    ) {
        vertices.append(TerrainVertex(
            position: SIMD4<Float>(position.x, position.y, position.z, 1),
            normal: SIMD4<Float>(normal.x, normal.y, normal.z, 0),
            color: color
        ))
    }

    private func terrainHeight(
        x: Float,
        z: Float,
        time: Float,
        frame: VisualAudioFrame,
        intensity: Float,
        isSkyRealm: Bool
    ) -> Float {
        let drift = SIMD2<Float>(sin(time * 0.035), cos(time * 0.027)) * 2.4
        let p = SIMD2<Float>(x, z)
        let broad = fbm(p * 0.030 + drift)
        let ridges = ridgedFbm(p * (isSkyRealm ? 0.080 : 0.068) + SIMD2<Float>(0, time * 0.030))
        let detail = fbm(p * 0.175 + SIMD2<Float>(broad * 2.0, ridges * 1.3))
        let valleyCenter = sin(z * 0.055 + time * 0.10) * (isSkyRealm ? 7.5 : 4.8)
        let valley = exp(-abs(x - valleyCenter) * (isSkyRealm ? 0.10 : 0.17))
        let terraces = sin((broad * 2.7 + ridges * 1.8 + z * 0.018) * 6.0) * 0.11
        if isSkyRealm {
            let islandLift = smoothstep(0.24, 0.92, ridges) * 5.2
            let cloudPlateau = smoothstep(0.42, 0.76, broad) * 2.0
            return 0.4 + islandLift + cloudPlateau + detail * 1.1 + terraces - valley * 0.7 + frame.smoothedBass * 0.18
        }
        let mountain = pow(max(0, ridges), 1.55) * 9.5 + broad * 3.1 + detail * 1.15
        return (mountain - 4.4 - valley * 1.3) * (0.70 + intensity * 0.34) + terraces + frame.smoothedBass * 0.28
    }

    private func terrainColor(
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        frame: VisualAudioFrame,
        palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
        time: Float,
        isSkyRealm: Bool
    ) -> SIMD4<Float> {
        let slope = 1 - max(0, normal.y)
        let ridgeDetail = ridgedFbm(SIMD2<Float>(position.x, position.z) * 0.22 + time * 0.015)
        let valley = exp(-abs(position.x - sin(position.z * 0.055 + time * 0.10) * (isSkyRealm ? 7.5 : 4.8)) * (isSkyRealm ? 0.10 : 0.17))
        let grass = isSkyRealm
            ? mix(SIMD3<Float>(0.18, 0.42, 0.28), palette.1 * 0.72, 0.45)
            : mix(SIMD3<Float>(0.12, 0.30, 0.20), palette.1 * 0.46, 0.38)
        let rock = mix(SIMD3<Float>(0.22, 0.23, 0.25), palette.0 * 0.34, 0.32)
        let snow = mix(SIMD3<Float>(0.72, 0.78, 0.78), palette.2 * 0.24 + SIMD3<Float>(0.45, 0.48, 0.52), 0.22)
        let water = mix(SIMD3<Float>(0.04, 0.15, 0.22), palette.0 * 0.64, 0.40)
        let mineral = mix(palette.2 * 0.70, SIMD3<Float>(0.70, 0.88, 0.94), 0.24)

        let rockMix = smoothstep(0.16, 0.66, slope + ridgeDetail * 0.22)
        let snowMix = smoothstep(isSkyRealm ? 5.7 : 4.8, isSkyRealm ? 9.8 : 8.5, position.y + ridgeDetail * 1.2)
        let waterMix = valley * smoothstep(isSkyRealm ? 2.2 : 1.0, isSkyRealm ? -0.2 : -1.3, position.y)
        let mineralMix = smoothstep(0.78, 1.0, ridgeDetail) * (0.10 + frame.trebleEnergy * 0.22)
        var color = mix(grass, rock, rockMix)
        color = mix(color, snow, snowMix * 0.62)
        color = mix(color, water, min(0.72, waterMix))
        color = mix(color, mineral, mineralMix)
        color += palette.1 * frame.smoothedBass * 0.035
        color += palette.2 * frame.trebleEnergy * smoothstep(0.52, 0.92, ridgeDetail) * 0.045
        return SIMD4<Float>(min(1, color.x), min(1, color.y), min(1, color.z), 1)
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

    private func ensureTerrainVertexBuffer(device: MTLDevice, vertexCount: Int) -> MTLBuffer? {
        if vertexCount > terrainVertexCapacity {
            terrainVertexCapacity = max(vertexCount, terrainVertexCapacity * 2, 16_384)
            terrainVertexBuffer = device.makeBuffer(
                length: MemoryLayout<TerrainVertex>.stride * terrainVertexCapacity,
                options: [.storageModeShared]
            )
        }
        return terrainVertexBuffer
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

    private func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        ))
    }

    private func lookAtMatrix(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    private func valueNoise(_ point: SIMD2<Float>) -> Float {
        let cell = SIMD2<Float>(floor(point.x), floor(point.y))
        var local = point - cell
        local = local * local * (SIMD2<Float>(repeating: 3) - local * 2)
        let a = hash(cell)
        let b = hash(cell + SIMD2<Float>(1, 0))
        let c = hash(cell + SIMD2<Float>(0, 1))
        let d = hash(cell + SIMD2<Float>(1, 1))
        return mix(mix(a, b, local.x), mix(c, d, local.x), local.y)
    }

    private func fbm(_ point: SIMD2<Float>) -> Float {
        var p = point
        var amplitude: Float = 0.52
        var value: Float = 0
        for _ in 0..<5 {
            value += valueNoise(p) * amplitude
            p = rotatePoint(p * 2.03 + SIMD2<Float>(17.31, 9.17), 0.47)
            amplitude *= 0.52
        }
        return value
    }

    private func ridgedFbm(_ point: SIMD2<Float>) -> Float {
        var p = point
        var amplitude: Float = 0.58
        var value: Float = 0
        for _ in 0..<5 {
            let ridge = 1 - abs(valueNoise(p) * 2 - 1)
            value += ridge * ridge * amplitude
            p = rotatePoint(p * 2.11 + SIMD2<Float>(5.13, 13.71), -0.38)
            amplitude *= 0.50
        }
        return min(1, value)
    }

    private func hash(_ point: SIMD2<Float>) -> Float {
        fract(sin(point.x * 127.1 + point.y * 311.7) * 43_758.5453)
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let range = edge1 - edge0
        guard abs(range) > 0.0001 else { return value < edge0 ? 0 : 1 }
        let t = min(1, max(0, (value - edge0) / range))
        return t * t * (3 - 2 * t)
    }

    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * min(1, max(0, t))
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

    struct TerrainVertex {
        float4 position;
        float4 normal;
        float4 color;
    };

    struct TerrainUniforms {
        float4x4 viewProjectionMatrix;
        float4 cameraPosition;
        float4 lightDirection;
        float4 fogColor;
        float4 audio;
        float fogStart;
        float fogEnd;
        float time;
        uint palette;
    };

    struct TerrainOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float4 color;
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

    vertex TerrainOut terrain_vertex(uint vertexID [[vertex_id]],
                                     constant TerrainVertex *vertices [[buffer(0)]],
                                     constant TerrainUniforms &uniforms [[buffer(1)]]) {
        TerrainVertex inputVertex = vertices[vertexID];
        TerrainOut out;
        float4 world = float4(inputVertex.position.xyz, 1.0);
        out.position = uniforms.viewProjectionMatrix * world;
        out.worldPosition = inputVertex.position.xyz;
        out.normal = normalize(inputVertex.normal.xyz);
        out.color = inputVertex.color;
        return out;
    }

    fragment half4 terrain_fragment(TerrainOut input [[stage_in]],
                                    constant TerrainUniforms &uniforms [[buffer(0)]]) {
        float3 normal = normalize(input.normal);
        float3 lightDirection = normalize(uniforms.lightDirection.xyz);
        float3 viewDirection = normalize(uniforms.cameraPosition.xyz - input.worldPosition);
        float diffuse = clamp(dot(normal, lightDirection), 0.0, 1.0);
        float halfLambert = diffuse * 0.5 + 0.5;
        float rim = pow(clamp(1.0 - dot(normal, viewDirection), 0.0, 1.0), 2.0);
        float distanceFromCamera = distance(uniforms.cameraPosition.xyz, input.worldPosition);
        float fog = smoothstep(uniforms.fogStart, uniforms.fogEnd, distanceFromCamera);
        float3 paletteLight = paletteGradient(uniforms.palette, 0.68 + uniforms.time * 0.018 + uniforms.audio.z * 0.08);
        float audioGlow = uniforms.audio.x * 0.055 + uniforms.audio.y * 0.070 + uniforms.audio.w * 0.045;
        float3 color = input.color.rgb * (0.24 + halfLambert * 0.86);
        color += paletteLight * (rim * (0.08 + uniforms.audio.z * 0.08) + audioGlow);
        color += paletteGradient(uniforms.palette, 0.36) * pow(diffuse, 6.0) * (0.05 + uniforms.audio.y * 0.06);
        color = lerp3(color, uniforms.fogColor.rgb, fog * 0.86);
        color = pow(max(color, float3(0.0)), float3(0.92));
        return half4(float4(clamp(color, 0.0, 1.0), 1.0));
    }

    float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float lerp1(float a, float b, float t) {
        return a + (b - a) * clamp(t, 0.0, 1.0);
    }

    float valueNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        float x0 = lerp1(a, b, f.x);
        float x1 = lerp1(c, d, f.x);
        return lerp1(x0, x1, f.y);
    }

    float fbm2(float2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        for (int octave = 0; octave < 5; octave++) {
            value += valueNoise(p) * amplitude;
            p = rotate2(p * 2.03 + float2(17.31, 9.17), 0.47);
            amplitude *= 0.52;
        }
        return value;
    }

    float ridgedFbm(float2 p) {
        float value = 0.0;
        float amplitude = 0.56;
        for (int octave = 0; octave < 5; octave++) {
            float ridge = 1.0 - abs(valueNoise(p) * 2.0 - 1.0);
            value += ridge * ridge * amplitude;
            p = rotate2(p * 2.11 + float2(5.13, 13.71), -0.38);
            amplitude *= 0.50;
        }
        return value;
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
        float2 drift = float2(sin(u.time * 0.045), cos(u.time * 0.038)) * (0.24 + u.motion * 0.22);
        float broad = fbm2(p * 0.34 + drift);
        float ridges = ridgedFbm(p * 0.78 + float2(0.0, u.time * 0.035));
        float detail = fbm2(p * 2.15 + broad * 1.2);
        float valley = exp(-abs(p.x + sin(p.y * 0.18 + u.time * 0.08) * 1.15) * 0.42);
        float terraces = sin((broad * 2.8 + ridges * 1.6 + p.y * 0.035) * 6.0) * 0.020;
        float mountain = pow(max(ridges, 0.0), 1.42) * 1.22 + broad * 0.62 + detail * 0.16;
        mountain -= valley * (0.18 + u.volume * 0.08);
        return (mountain - 0.74) * (0.48 + u.intensity * 0.34) + terraces + u.bass * 0.055;
    }

    float4 terrainFlight(float2 point, constant FractalUniforms &u) {
        float speed = 0.72 + u.motion * 1.55 + u.volume * 0.30 + u.beat * 0.22;
        float travel = u.time * speed;
        float3 camera = float3(
            sin(travel * 0.18) * 1.8 + sin(travel * 0.051) * 2.5,
            0.74 + u.volume * 0.18 + u.bass * 0.10,
            travel * 2.7
        );
        float3 ray = normalize(float3(point.x * 0.94, point.y * 0.66 - 0.18 + u.mid * 0.035, 1.42));
        ray.xz = rotate2(ray.xz, sin(travel * 0.073) * 0.24 + u.mid * 0.04);

        float3 skyLow = paletteGradient(u.palette, 0.56 + point.y * 0.08) * 0.22;
        float3 skyHigh = paletteGradient(u.palette, 0.84 + u.time * 0.018) * 0.12 + float3(0.015, 0.020, 0.035);
        float skyMix = smoothstep(-0.65, 0.85, point.y);
        float3 color = lerp3(skyLow, skyHigh, skyMix);
        float2 sunPos = float2(0.52 + sin(u.time * 0.025) * 0.16, 0.42 + cos(u.time * 0.021) * 0.06);
        float sun = exp(-length(point - sunPos) * 5.2);
        color += paletteGradient(u.palette, 0.11) * sun * (0.18 + u.glow * 0.18);

        float closest = 10.0;
        float hitAmount = 0.0;
        float t = 0.08;
        float hitHeight = 0.0;
        float3 hitPosition = camera;
        for (int i = 0; i < 78; i++) {
            float3 pos = camera + ray * t;
            float height = terrainHeight(pos.xz, u);
            float distanceToGround = pos.y - height;
            closest = min(closest, abs(distanceToGround));
            if (distanceToGround < 0.012) {
                float eps = 0.045;
                float hx = terrainHeight(pos.xz + float2(eps, 0.0), u) - terrainHeight(pos.xz - float2(eps, 0.0), u);
                float hz = terrainHeight(pos.xz + float2(0.0, eps), u) - terrainHeight(pos.xz - float2(0.0, eps), u);
                float3 normal = normalize(float3(-hx, 0.12, -hz));
                float3 lightDirection = normalize(float3(-0.58, 0.78, -0.34));
                float light = clamp(dot(normal, lightDirection), 0.0, 1.0);
                float rim = pow(clamp(dot(normal, normalize(float3(0.44, 0.36, -0.80))), 0.0, 1.0), 2.0);
                float fog = exp(-t * (0.105 - u.glow * 0.025));
                float ridgeLight = smoothstep(0.42, 0.95, light) + u.treble * 0.12 + u.beat * 0.08;
                float snow = smoothstep(0.45, 1.05, height + ridgedFbm(pos.xz * 1.4) * 0.18);
                float river = exp(-abs(pos.x + sin(pos.z * 0.18) * 0.95) * 2.5) * smoothstep(0.38, -0.20, height);
                float path = exp(-abs(pos.x - sin(pos.z * 0.11 + 1.7) * 1.3) * 1.55) * smoothstep(0.42, -0.08, height);
                float3 ground = paletteGradient(u.palette, 0.18 + height * 0.30 + t * 0.018) * (0.24 + light * 0.80 + ridgeLight * 0.16);
                float3 snowColor = float3(0.72, 0.82, 0.86) * (0.35 + light * 0.70);
                float3 waterColor = paletteGradient(u.palette, 0.58 + u.time * 0.020) * (0.42 + rim * 0.50 + u.glow * 0.16);
                color = lerp3(ground, snowColor, snow * 0.42);
                color = lerp3(color, waterColor, river * (0.36 + u.glow * 0.20));
                color += paletteGradient(u.palette, 0.30) * path * (0.08 + u.bass * 0.08);
                color += paletteGradient(u.palette, 0.72) * rim * (0.12 + u.glow * 0.20);
                color *= fog;
                hitHeight = height;
                hitPosition = pos;
                hitAmount = 1.0;
                break;
            }
            t += max(0.030, abs(distanceToGround) * 0.40 + t * 0.014);
        }

        float horizon = smoothstep(-0.18, 0.58, point.y + u.volume * 0.06);
        float glow = exp(-closest * (5.2 + u.glow * 7.0)) * (0.08 + u.bass * 0.18 + u.beat * 0.10);
        float cloud = smoothstep(0.54, 0.90, fbm2(point * float2(2.1, 0.8) + float2(travel * 0.035, u.time * 0.015)));
        color += paletteGradient(u.palette, 0.78 + u.time * 0.035) * horizon * (0.06 + u.glow * 0.13);
        color += paletteGradient(u.palette, 0.32 + u.treble * 0.20) * glow;
        color += cloud * (1.0 - hitAmount) * paletteGradient(u.palette, 0.68) * 0.09;
        color += transientDust(point * 0.74, u) * paletteGradient(u.palette, 0.92) * 0.55;
        color *= 0.82 + hitAmount * 0.34;
        color = pow(max(color, float3(0.0)), float3(0.92));
        color += paletteGradient(u.palette, 0.46 + hitHeight * 0.10) * exp(-length(hitPosition.xz - camera.xz) * 0.075) * hitAmount * 0.035;
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

    float4 skyRealmFlight(float2 point, constant FractalUniforms &u) {
        float travel = u.time * (0.34 + u.motion * 0.70 + u.volume * 0.12 + u.beat * 0.10);
        float2 skyPoint = point + float2(sin(travel * 0.11) * 0.10, cos(travel * 0.07) * 0.035);
        float3 horizon = paletteGradient(u.palette, 0.56 + skyPoint.y * 0.08) * 0.24 + float3(0.015, 0.020, 0.038);
        float3 zenith = paletteGradient(u.palette, 0.82 + u.time * 0.018) * 0.11 + float3(0.010, 0.018, 0.034);
        float3 color = lerp3(horizon, zenith, smoothstep(-0.75, 0.95, skyPoint.y));

        float2 sunPosition = float2(0.48 + sin(u.time * 0.020) * 0.12, 0.34 + cos(u.time * 0.018) * 0.08);
        float sun = exp(-length(point - sunPosition) * 5.6);
        float halo = exp(-length(point - sunPosition) * 1.6);
        color += paletteGradient(u.palette, 0.12) * sun * (0.30 + u.glow * 0.28);
        color += paletteGradient(u.palette, 0.18) * halo * 0.055;

        float cloud = fbm2(point * float2(1.8, 0.72) + float2(travel * 0.08, u.time * 0.018));
        float cloudMask = smoothstep(0.48, 0.82, cloud + smoothstep(0.20, 0.92, point.y) * 0.25);
        color += cloudMask * paletteGradient(u.palette, 0.66) * (0.055 + u.glow * 0.035);

        for (int layer = 0; layer < 10; layer++) {
            float lf = float(layer);
            float depth = 1.0 + lf * 0.62;
            float lane = fract(travel * (0.16 + lf * 0.010) + lf * 0.173);
            float z = 0.42 + lane * 3.2;
            float scale = 1.0 / z;
            float2 center = float2(
                sin(lf * 2.17 + travel * 0.19) * (0.52 + lf * 0.040),
                -0.34 + sin(lf * 1.31 + travel * 0.13) * 0.20 + (1.0 - lane) * 0.38
            ) * scale;
            float islandSize = (0.22 + hash21(float2(lf, 4.2)) * 0.20) * scale;
            float2 local = (point - center) / max(islandSize, 0.001);
            local.x += sin(local.y * 2.4 + lf) * 0.11;
            float landNoise = ridgedFbm(local * 1.75 + lf);
            float body = smoothstep(0.90, 0.42, length(local * float2(0.92, 1.42)) + landNoise * 0.20);
            float top = body * smoothstep(-0.20, 0.22, local.y + landNoise * 0.12);
            float underside = body * smoothstep(0.28, -0.38, local.y);
            float grass = smoothstep(-0.05, 0.38, local.y + landNoise * 0.10);
            float fog = exp(-depth * 0.16);
            float3 rock = paletteGradient(u.palette, 0.22 + landNoise * 0.20) * (0.26 + fog * 0.28);
            float3 meadow = paletteGradient(u.palette, 0.42 + landNoise * 0.13) * (0.36 + fog * 0.34 + u.bass * 0.06);
            float3 islandColor = lerp3(rock, meadow, grass);
            islandColor += paletteGradient(u.palette, 0.72) * underside * (0.08 + u.glow * 0.08);
            color = lerp3(color, islandColor, clamp((top + underside * 0.82) * fog, 0.0, 0.78));

            float towerBase = smoothstep(0.055, 0.018, abs(local.x + sin(lf) * 0.15));
            float towerHeight = smoothstep(-0.10, 0.54, local.y) * smoothstep(1.10, 0.42, local.y);
            float spire = towerBase * towerHeight * top * step(0.54, hash21(float2(lf, 8.3)));
            color += paletteGradient(u.palette, 0.88 + lf * 0.03) * spire * fog * (0.22 + u.glow * 0.20);
        }

        float aurora = spectralFilament(point * float2(0.75, 1.18) + float2(0.0, 0.18), u);
        color += paletteGradient(u.palette, 0.78 + u.time * 0.025) * aurora * (0.07 + u.treble * 0.08 + u.glow * 0.06);
        color += transientDust(point * 0.68, u) * paletteGradient(u.palette, 0.95) * 0.42;
        color = pow(max(color, float3(0.0)), float3(0.90));
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }

    float crystalFacet(float2 p, float angle, float sharpness) {
        float2 q = rotate2(p, angle);
        float diamond = max(abs(q.x) * 0.72 + abs(q.y) * 1.18, abs(q.x + q.y) * 0.52);
        return 1.0 - smoothstep(sharpness, 1.0, diamond);
    }

    float4 crystalCavern(float2 point, constant FractalUniforms &u) {
        float travel = u.time * (0.42 + u.motion * 0.78 + u.volume * 0.16 + u.beat * 0.10);
        float radius = length(point * float2(0.92, 1.08));
        float angle = atan2(point.y, point.x);
        float tunnel = smoothstep(0.08, 1.34, radius);
        float3 color = float3(0.006, 0.008, 0.015) + paletteGradient(u.palette, 0.62 + point.y * 0.08) * 0.050;

        float wallNoise = ridgedFbm(float2(angle * 1.7, radius * 3.4 - travel * 0.55));
        float wall = smoothstep(0.34, 1.05, radius + wallNoise * 0.16);
        color += paletteGradient(u.palette, 0.18 + wallNoise * 0.32) * wall * (0.11 + u.glow * 0.10);

        for (int layer = 0; layer < 13; layer++) {
            float lf = float(layer);
            float depth = fract(travel * (0.18 + lf * 0.004) + lf * 0.137);
            float scale = 0.30 + depth * 2.55;
            float side = (hash21(float2(lf, 2.0)) < 0.5) ? -1.0 : 1.0;
            float lane = side * (0.54 + hash21(float2(lf, 5.0)) * 0.56);
            float y = -0.22 + sin(lf * 1.9 + travel * 0.36) * 0.42;
            float2 center = float2(lane / scale, y / scale);
            float crystalSize = (0.18 + hash21(float2(lf, 9.0)) * 0.18) / scale;
            float2 local = (point - center) / max(crystalSize, 0.001);
            float facet = crystalFacet(local, lf * 0.41 + travel * 0.035, 0.46);
            float core = crystalFacet(local * 1.45 + float2(0.12, -0.08), -lf * 0.22, 0.38);
            float edge = smoothstep(0.40, 1.00, facet) - smoothstep(0.72, 1.00, facet);
            float fog = exp(-scale * 0.17);
            float sparkle = smoothstep(0.70, 0.98, valueNoise(local * 4.0 + lf + u.time * 0.15));
            float3 crystal = paletteGradient(u.palette, 0.50 + lf * 0.055 + u.treble * 0.08)
                * (0.22 + core * 0.38 + edge * 0.55 + sparkle * u.treble * 0.20);
            color += crystal * facet * fog * (0.72 + u.glow * 0.42 + u.beat * 0.18);
        }

        float path = exp(-abs(point.y + 0.72 + sin(point.x * 3.4 + travel) * 0.025) * 9.0) * smoothstep(0.92, 0.08, abs(point.x));
        float rune = smoothstep(0.94, 1.0, sin(point.x * 34.0 + travel * 2.6) * 0.5 + 0.5) * path;
        color += paletteGradient(u.palette, 0.76 + u.time * 0.025) * path * (0.08 + u.bass * 0.10);
        color += paletteGradient(u.palette, 0.92) * rune * (0.20 + u.glow * 0.18);

        float centerGlow = exp(-radius * (2.2 + u.glow * 1.6));
        color += paletteGradient(u.palette, 0.60 + u.time * 0.020) * centerGlow * (0.08 + u.volume * 0.08);
        color += spectralFilament(point * 0.95, u) * paletteGradient(u.palette, 0.83) * (0.05 + u.treble * 0.08);
        color += transientDust(point * 1.1, u) * paletteGradient(u.palette, 0.98) * 0.45;
        color *= smoothstep(1.55, 0.08, radius) * 0.72 + wall * 0.42;
        color = pow(max(color, float3(0.0)), float3(0.88));
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }

    float4 iterateFractal(float2 point, constant FractalUniforms &u) {
        if (u.mode == 5) {
            return mandelboxFlight(point, u);
        }
        if (u.mode == 6) {
            return nebulaVoyage(point, u);
        }
        if (u.mode == 7) {
            return crystalCavern(point, u);
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
