import Metal
import MetalKit
import SpectraCore
import simd

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let frameStore: VisualFrameStore
    private var presetProvider: () -> VisualPresetID
    private var settingsProvider: () -> PresetSettings
    private let fpsHandler: (Double) -> Void

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
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
        self.pipelineState = makePipeline(for: view)
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
              let pipelineState,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        let frame = frameStore.read()
        let settings = settingsProvider()
        let preset = presetProvider()
        let time = Float(CACurrentMediaTime() - startTime)
        reusableVertices.removeAll(keepingCapacity: true)
        appendVertices(into: &reusableVertices, for: preset, frame: frame, settings: settings, time: time)

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

    private func makePipeline(for view: MTKView) -> MTLRenderPipelineState? {
        guard let device = view.device else { return nil }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            assertionFailure("Spectra Metal shader compilation failed: \(error.localizedDescription)")
            return nil
        }
        guard let vertexFunction = library.makeFunction(name: "spectra_vertex"),
              let fragmentFunction = library.makeFunction(name: "spectra_fragment") else {
            assertionFailure("Spectra Metal shader library is missing required functions.")
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
        time: Float
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
    """
}
