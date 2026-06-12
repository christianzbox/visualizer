import Foundation

public final class TestSignalCaptureEngine: AudioCaptureEngine {
    public private(set) var isRunning = false
    public private(set) var currentSource: AudioSource?
    public let sampleRate: Double
    public let channelCount: Int

    public var signalType: TestSignalType {
        get { stateQueue.sync { _signalType } }
        set { stateQueue.sync { _signalType = newValue } }
    }

    private let bufferSize: Int
    private let source = AudioSource(id: "test-signal", name: "Test Signal", kind: .testSignal)
    private let generationQueue = DispatchQueue(label: "spectra.test-signal", qos: .userInteractive)
    private let stateQueue = DispatchQueue(label: "spectra.test-signal.state")
    private var timer: DispatchSourceTimer?
    private var sampleCursor: Double = 0
    private var noiseState: UInt64 = 0x1234_5678_ABCD_EF01
    private var handler: AudioBufferHandler?
    private var _signalType: TestSignalType

    public init(
        signalType: TestSignalType = .beatPattern,
        sampleRate: Double = 48_000,
        channelCount: Int = 2,
        bufferSize: Int = 512
    ) {
        self._signalType = signalType
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bufferSize = bufferSize
        self.currentSource = source
    }

    public func listSources() async throws -> [AudioSource] {
        [source]
    }

    public func selectSource(_ source: AudioSource) async throws {
        guard source.id == self.source.id else {
            throw AudioCaptureError.sourceNotFound(source.id)
        }
        currentSource = source
    }

    public func setAudioBufferHandler(_ handler: @escaping AudioBufferHandler) {
        stateQueue.sync {
            self.handler = handler
        }
    }

    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: generationQueue)
        let interval = DispatchTimeInterval.nanoseconds(Int((Double(bufferSize) / sampleRate) * 1_000_000_000))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(500))
        timer.setEventHandler { [weak self] in
            self?.emitBuffer()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    private func emitBuffer() {
        let signal = stateQueue.sync { _signalType }
        let localHandler = stateQueue.sync { handler }
        guard let localHandler else { return }

        var samples = Array(repeating: Float(0), count: bufferSize * channelCount)
        let timestamp = Date().timeIntervalSince1970
        let beatFrequency = 2.0

        for frame in 0..<bufferSize {
            let t = (sampleCursor + Double(frame)) / sampleRate
            let sample: Float
            switch signal {
            case .sine:
                sample = Float(sin(2 * Double.pi * 440 * t) * 0.42)
            case .bassPulse:
                let beatPhase = (t * beatFrequency).truncatingRemainder(dividingBy: 1)
                let envelope = exp(-beatPhase * 9)
                sample = Float(sin(2 * Double.pi * 72 * t) * envelope * 0.86)
            case .noise:
                sample = nextNoiseSample() * 0.32
            case .beatPattern:
                let beatPhase = (t * beatFrequency).truncatingRemainder(dividingBy: 1)
                let kick = sin(2 * Double.pi * 58 * t) * exp(-beatPhase * 12)
                let lead = sin(2 * Double.pi * 660 * t) * 0.16
                let hatGate = beatPhase > 0.48 && beatPhase < 0.56 ? 1.0 : 0.0
                let hat = Double(nextNoiseSample()) * hatGate * 0.18
                sample = Float((kick * 0.82) + lead + hat)
            }

            for channel in 0..<channelCount {
                samples[(frame * channelCount) + channel] = sample
            }
        }

        sampleCursor += Double(bufferSize)
        if sampleCursor > sampleRate * 60 * 60 {
            sampleCursor = sampleCursor.truncatingRemainder(dividingBy: sampleRate)
        }

        localHandler(AudioBufferFrame(
            timestamp: timestamp,
            sampleRate: sampleRate,
            channelCount: channelCount,
            frames: bufferSize,
            samples: samples,
            sourceId: source.id
        ))
    }

    private func nextNoiseSample() -> Float {
        noiseState = 6_364_136_223_846_793_005 &* noiseState &+ 1
        let value = UInt32(truncatingIfNeeded: noiseState >> 32)
        return (Float(value) / Float(UInt32.max)) * 2 - 1
    }
}
