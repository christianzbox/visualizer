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

        let frame = frameStore.read()
        let settings = settingsProvider()
        let preset = presetProvider()
        let time = Float(CACurrentMediaTime() - startTime)
        let isFractal = preset.isFractal
        reusableVertices.removeAll(keepingCapacity: true)
        appendVertices(
            into: &reusableVertices,
            for: preset,
            frame: frame,
            settings: settings,
            time: time,
            drawableSize: view.drawableSize
        )
        guard let pipelineState = isFractal ? fractalPipelineState : geometryPipelineState else { return }

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
        if isFractal {
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
        lastFrameTime = CACurrentMediaTime()
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
        case .mandelbrotBloom, .juliaVortex, .burningShip, .tricornPulse, .phoenixField:
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
        vertices.reserveCapacity(count * 12)

        for index in 0..<count {
            let x0 = -0.94 + (Float(index) / Float(count)) * 1.88
            let x1 = -0.94 + (Float(index + 1) / Float(count)) * 1.88 - 0.006
            let energy = pow(min(1, bands[index] * sensitivity * 1.45), 0.72)
            let height = max(0.018, energy * 1.38 * intensity)
            let y0: Float = -0.78
            let y1 = min(0.88, y0 + height + beat * 0.08)
            let shimmer = 0.06 * sin(time * 3.2 + Float(index) * 0.37) * frame.trebleEnergy
            let color = mix(palette.0, palette.1, Float(index) / Float(count))
            let topColor = SIMD4<Float>(
                min(1, color.x + 0.18 + shimmer),
                min(1, color.y + 0.12),
                min(1, color.z + 0.22),
                0.84
            )
            let bottomColor = SIMD4<Float>(color.x * 0.36, color.y * 0.36, color.z * 0.42, 0.78)
            appendQuad(&vertices, x0: x0, y0: y0, x1: x1, y1: y1, bottom: bottomColor, top: topColor)

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
        let thickness = 0.012 + frame.smoothedBass * 0.038 * intensity
        let count = min(180, waveform.count)
        vertices.reserveCapacity(max(0, (count - 1) * 6))

        for index in 0..<(count - 1) {
            let t0 = Float(index) / Float(count - 1)
            let t1 = Float(index + 1) / Float(count - 1)
            let x0 = -0.92 + t0 * 1.84
            let x1 = -0.92 + t1 * 1.84
            let wave0 = waveform[index] * sensitivity * 0.56
            let wave1 = waveform[index + 1] * sensitivity * 0.56
            let liquid0 = sin((t0 * 9.0) + time * 0.9) * frame.bassEnergy * 0.05
            let liquid1 = sin((t1 * 9.0) + time * 0.9) * frame.bassEnergy * 0.05
            let y0 = wave0 + liquid0
            let y1 = wave1 + liquid1
            let color = mix(palette.1, palette.2, t0)
            let alpha = 0.60 + frame.smoothedVolume * 0.28
            let topColor = SIMD4<Float>(color.x, color.y, color.z, alpha)
            let bottomColor = SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, alpha * 0.65)

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
        let particleCount = 380
        let sensitivity = Float(settings.sensitivity)
        let intensity = Float(settings.intensity)
        let beat = frame.beatPulse * Float(settings.beatReactivity)
        let motion = settings.reduceMotion ? Float(0.18) : Float(settings.motionAmount)
        vertices.reserveCapacity(particleCount * 6)

        for index in 0..<particleCount {
            let seed = Float(index)
            let ring = fract(sin(seed * 12.9898) * 43_758.5453)
            let angleSeed = fract(sin(seed * 78.233) * 18_234.123)
            let radius = 0.08 + pow(ring, 0.62) * (0.76 + frame.bassEnergy * 0.28 + beat * 0.22)
            let angle = angleSeed * Float.pi * 2 + time * (0.04 + motion * 0.16) * (0.4 + ring)
            let spiral = frame.midEnergy * 0.22 * sin(time * 0.7 + seed * 0.13)
            let x = cos(angle + spiral) * radius
            let y = sin(angle + spiral) * radius * 0.78
            let shimmer = 0.35 + frame.trebleEnergy * sensitivity * fract(sin(seed * 91.7 + time * 5.0) * 111.1)
            let size = (0.0035 + ring * 0.006 + beat * 0.006) * (0.75 + intensity)
            let color = mix(palette.0, palette.2, ring)
            let alpha = min(0.86, 0.16 + shimmer * 0.52 + frame.smoothedVolume * 0.22)
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

        let core = 0.06 + frame.smoothedBass * 0.22 + beat * 0.16
        appendQuad(
            &vertices,
            x0: -core,
            y0: -core,
            x1: core,
            y1: core,
            bottom: SIMD4<Float>(palette.1.x, palette.1.y, palette.1.z, 0.08),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.34)
        )
    }

    private func neonTunnel(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let palette = paletteColors(settings.palette)
        let ringCount = 30
        let segmentCount = 88
        let beat = frame.beatPulse * Float(settings.beatReactivity)
        let motion = settings.reduceMotion ? Float(0.12) : Float(settings.motionAmount)
        vertices.reserveCapacity(ringCount * segmentCount * 6)

        for ring in 0..<ringCount {
            let depth = Float(ring) / Float(ringCount)
            let radius = 0.08 + pow(depth, 1.35) * (1.14 + beat * 0.24)
            let twist = time * (0.22 + motion * 0.5) + depth * 3.4 + frame.smoothedBass * 0.35
            let width = 0.0028 + (1 - depth) * 0.005 + frame.trebleEnergy * 0.004
            let color = mix(palette.0, palette.2, depth)
            let alpha = (1 - depth) * 0.42 + frame.smoothedVolume * 0.18

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
    }

    private func minimalWaveform(into vertices: inout [SpectraVertex], frame: VisualAudioFrame, settings: PresetSettings, time: Float) {
        let waveform = frame.waveform.isEmpty ? VisualAudioFrame.silent.waveform : frame.waveform
        let palette = paletteColors(settings.palette)
        let count = min(150, waveform.count)
        let sensitivity = Float(settings.sensitivity) * 0.36
        let thickness: Float = 0.006 + frame.smoothedVolume * 0.012
        vertices.reserveCapacity(max(0, (count - 1) * 6) + 12)

        appendQuad(
            &vertices,
            x0: -0.86,
            y0: -0.004,
            x1: 0.86,
            y1: 0.004,
            bottom: SIMD4<Float>(palette.0.x, palette.0.y, palette.0.z, 0.16),
            top: SIMD4<Float>(palette.2.x, palette.2.y, palette.2.z, 0.18)
        )

        for index in 0..<(count - 1) {
            let t0 = Float(index) / Float(count - 1)
            let t1 = Float(index + 1) / Float(count - 1)
            let x0 = -0.86 + t0 * 1.72
            let x1 = -0.86 + t1 * 1.72
            let drift0 = sin(time * 0.45 + t0 * 5.2) * frame.smoothedBass * 0.02
            let drift1 = sin(time * 0.45 + t1 * 5.2) * frame.smoothedBass * 0.02
            let y0 = waveform[index] * sensitivity + drift0
            let y1 = waveform[index + 1] * sensitivity + drift1
            let color = mix(palette.1, palette.2, t0)
            appendRibbonSegment(
                &vertices,
                x0: x0,
                y0: y0,
                x1: x1,
                y1: y1,
                halfThickness: thickness,
                colorA: SIMD4<Float>(color.x, color.y, color.z, 0.48),
                colorB: SIMD4<Float>(min(1, color.x + 0.12), min(1, color.y + 0.12), min(1, color.z + 0.12), 0.62)
            )
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
        let mode = UInt32(max(0, preset.fractalMode ?? 0))
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

    float4 iterateFractal(float2 point, constant FractalUniforms &u) {
        float audio = clamp(u.volume * (0.78 + u.sensitivity), 0.0, 1.0);
        float bass = clamp(u.bass * (0.78 + u.sensitivity), 0.0, 1.2);
        float mid = clamp(u.mid * (0.78 + u.sensitivity), 0.0, 1.2);
        float treble = clamp(u.treble * (0.78 + u.sensitivity), 0.0, 1.2);
        float beat = clamp(u.beat * u.beatReactivity, 0.0, 1.0);
        float travel = u.time * (0.018 + u.motion * 0.090);
        float rotateAmount = sin(travel * 0.73 + mid * 1.7) * (0.10 + u.motion * 0.42);
        float zoom = 1.0 + bass * 0.28 + beat * 0.20 + audio * 0.14;
        float2 p = rotate2(point, rotateAmount) / zoom;
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
