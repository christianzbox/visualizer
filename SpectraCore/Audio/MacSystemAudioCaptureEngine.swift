import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public final class MacSystemAudioCaptureEngine: NSObject, AudioCaptureEngine {
    public private(set) var isRunning = false
    public private(set) var currentSource: AudioSource?
    public private(set) var sampleRate: Double = 48_000
    public private(set) var channelCount: Int = 2

    private let outputQueue = DispatchQueue(label: "spectra.system-audio.output", qos: .userInteractive)
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var handler: AudioBufferHandler?
    private let systemSource = AudioSource(
        id: "system-mix",
        name: "System Mix",
        kind: .systemMix
    )

    public override init() {
        self.currentSource = systemSource
        super.init()
    }

    public func listSources() async throws -> [AudioSource] {
        guard Self.isSupportedRuntime else {
            throw AudioCaptureError.unsupportedOS(Self.unsupportedOSMessage)
        }

        var sources = [systemSource]
        let content = try await Self.loadShareableContent()
        let appSources = content.applications.map { app in
            AudioSource(
                id: "app-\(app.processID)",
                name: app.applicationName,
                kind: .application,
                processId: Int(app.processID),
                bundleIdentifier: app.bundleIdentifier
            )
        }
        sources.append(contentsOf: appSources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        return sources
    }

    public func selectSource(_ source: AudioSource) async throws {
        switch source.kind {
        case .systemMix, .application:
            currentSource = source
        case .device, .testSignal:
            throw AudioCaptureError.sourceNotFound(source.id)
        }
    }

    public func setAudioBufferHandler(_ handler: @escaping AudioBufferHandler) {
        self.handler = handler
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard Self.isSupportedRuntime else {
            throw AudioCaptureError.unsupportedOS(Self.unsupportedOSMessage)
        }

        let content = try await Self.loadShareableContent()

        guard let display = content.displays.first else {
            throw AudioCaptureError.noSourcesAvailable
        }

        let source = currentSource ?? systemSource
        let filter: SCContentFilter
        if source.kind == .application, let processId = source.processId {
            guard let app = content.applications.first(where: { Int($0.processID) == processId }) else {
                throw AudioCaptureError.sourceNotFound(source.id)
            }
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Int(sampleRate)
        configuration.channelCount = channelCount
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        configuration.queueDepth = 3

        let output = StreamOutput(sourceId: source.id) { [weak self] frame in
            self?.handler?(frame)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        do {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
        } catch {
            throw Self.mapStreamStartError(error)
        }

        streamOutput = output
        self.stream = stream
        isRunning = true
    }

    public func stop() async {
        guard isRunning else { return }
        if let stream, let streamOutput {
            try? stream.removeStreamOutput(streamOutput, type: .audio)
            try? await stream.stopCapture()
        }
        streamOutput = nil
        stream = nil
        isRunning = false
    }

    private static var isSupportedRuntime: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    private static var unsupportedOSMessage: String {
        "Spectra system audio capture requires macOS 13 or newer. Test Signal Mode is available on this Mac."
    }

    private static func loadShareableContent() async throws -> SCShareableContent {
        do {
            if #available(macOS 14.4, *) {
                return try await SCShareableContent.currentProcess
            }
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw mapShareableContentError(error)
        }
    }

    private static func mapShareableContentError(_ error: Error) -> AudioCaptureError {
        if isPermissionError(error) {
            return .permissionDenied
        }
        return .backendUnavailable("ScreenCaptureKit could not enumerate audio sources: \(describe(error))")
    }

    private static func mapStreamStartError(_ error: Error) -> AudioCaptureError {
        if isPermissionError(error) {
            return .permissionDenied
        }
        return .streamStartFailed("ScreenCaptureKit could not start audio capture: \(describe(error))")
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        return nsError.code == -3801 || nsError.code == -3803
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (domain \(nsError.domain), code \(nsError.code))"
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    private let sourceId: String
    private let handler: AudioBufferHandler

    init(sourceId: String, handler: @escaping AudioBufferHandler) {
        self.sourceId = sourceId
        self.handler = handler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let frame = Self.makeAudioFrame(from: sampleBuffer, sourceId: sourceId) else { return }
        handler(frame)
    }

    private static func makeAudioFrame(from sampleBuffer: CMSampleBuffer, sourceId: String) -> AudioBufferFrame? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let asbd = streamDescription.pointee
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        let bufferList = AudioBufferList.allocate(maximumBuffers: channelCount)
        defer { bufferList.unsafeMutablePointer.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: channelCount),
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            return nil
        }

        let flags = asbd.mFormatFlags
        let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (flags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)
        guard (isFloat && bitsPerChannel == 32) || (isSignedInteger && (bitsPerChannel == 16 || bitsPerChannel == 32)) else {
            return nil
        }

        var samples = Array(repeating: Float(0), count: frameCount * channelCount)
        if isNonInterleaved {
            for channel in 0..<min(channelCount, bufferList.count) {
                guard let data = bufferList[channel].mData else { continue }
                if isFloat {
                    let pointer = data.assumingMemoryBound(to: Float.self)
                    for frame in 0..<frameCount {
                        samples[(frame * channelCount) + channel] = pointer[frame]
                    }
                } else if bitsPerChannel == 16 {
                    let pointer = data.assumingMemoryBound(to: Int16.self)
                    for frame in 0..<frameCount {
                        samples[(frame * channelCount) + channel] = Float(pointer[frame]) / Float(Int16.max)
                    }
                } else {
                    let pointer = data.assumingMemoryBound(to: Int32.self)
                    for frame in 0..<frameCount {
                        samples[(frame * channelCount) + channel] = Float(pointer[frame]) / Float(Int32.max)
                    }
                }
            }
        } else {
            guard let data = bufferList[0].mData else { return nil }
            let count = frameCount * channelCount
            if isFloat {
                let pointer = data.assumingMemoryBound(to: Float.self)
                samples.withUnsafeMutableBufferPointer { destination in
                    destination.baseAddress?.update(from: pointer, count: count)
                }
            } else if bitsPerChannel == 16 {
                let pointer = data.assumingMemoryBound(to: Int16.self)
                for index in 0..<count {
                    samples[index] = Float(pointer[index]) / Float(Int16.max)
                }
            } else {
                let pointer = data.assumingMemoryBound(to: Int32.self)
                for index in 0..<count {
                    samples[index] = Float(pointer[index]) / Float(Int32.max)
                }
            }
        }

        return AudioBufferFrame(
            timestamp: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
            sampleRate: asbd.mSampleRate,
            channelCount: channelCount,
            frames: frameCount,
            samples: samples,
            sourceId: sourceId
        )
    }
}
