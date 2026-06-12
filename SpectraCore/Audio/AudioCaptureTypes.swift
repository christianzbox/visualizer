import Foundation

public enum AudioSourceKind: String, Codable, CaseIterable, Sendable {
    case systemMix
    case application
    case device
    case testSignal
}

public struct AudioSource: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var kind: AudioSourceKind
    public var processId: Int?
    public var bundleIdentifier: String?
    public var iconName: String?

    public init(
        id: String,
        name: String,
        kind: AudioSourceKind,
        processId: Int? = nil,
        bundleIdentifier: String? = nil,
        iconName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.processId = processId
        self.bundleIdentifier = bundleIdentifier
        self.iconName = iconName
    }
}

public struct AudioBufferFrame: Sendable {
    public let timestamp: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int
    public let frames: Int
    public let samples: [Float]
    public let sourceId: String

    public init(
        timestamp: TimeInterval,
        sampleRate: Double,
        channelCount: Int,
        frames: Int,
        samples: [Float],
        sourceId: String
    ) {
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frames = frames
        self.samples = samples
        self.sourceId = sourceId
    }
}

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case systemMix
    case application
    case testSignal

    public var label: String {
        switch self {
        case .systemMix: return "System Mix"
        case .application: return "App Source"
        case .testSignal: return "Test Signal"
        }
    }
}

public enum TestSignalType: String, Codable, CaseIterable, Sendable {
    case sine
    case bassPulse
    case noise
    case beatPattern

    public var label: String {
        switch self {
        case .sine: return "Sine"
        case .bassPulse: return "Bass Pulse"
        case .noise: return "Noise"
        case .beatPattern: return "Beat Pattern"
        }
    }
}

public enum AudioCaptureError: LocalizedError, Equatable, Sendable {
    case noSourcesAvailable
    case sourceNotFound(String)
    case permissionDenied
    case unsupportedOS(String)
    case unsupportedFormat(String)
    case backendUnavailable(String)
    case streamStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSourcesAvailable:
            return "No audio sources are available."
        case .sourceNotFound(let id):
            return "The selected audio source could not be found: \(id)."
        case .permissionDenied:
            return "Spectra needs Screen & System Audio Recording permission to capture system output."
        case .unsupportedOS(let message):
            return message
        case .unsupportedFormat(let message):
            return message
        case .backendUnavailable(let message):
            return message
        case .streamStartFailed(let message):
            return message
        }
    }

    public var failureReason: String? {
        switch self {
        case .permissionDenied:
            return "macOS has not granted Screen & System Audio Recording access to Spectra."
        case .unsupportedOS:
            return "This macOS version does not expose the ScreenCaptureKit system-audio capture APIs Spectra uses."
        case .unsupportedFormat:
            return "The capture stream returned an audio format Spectra does not currently convert."
        case .backendUnavailable:
            return "The macOS audio capture backend could not be initialized."
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Open System Settings, grant Screen & System Audio Recording permission, then restart capture. Test Signal Mode remains available."
        case .unsupportedOS:
            return "Use Test Signal Mode on this Mac, or run Spectra on macOS 13 or newer for system audio capture."
        case .unsupportedFormat:
            return "Use Test Signal Mode and report the source format so the converter can be extended."
        case .backendUnavailable, .streamStartFailed, .noSourcesAvailable:
            return "Use Test Signal Mode while system capture is unavailable."
        case .sourceNotFound:
            return "Refresh sources or switch to System Mix/Test Signal Mode."
        }
    }
}

public typealias AudioBufferHandler = @Sendable (AudioBufferFrame) -> Void

public protocol AudioCaptureEngine: AnyObject {
    var isRunning: Bool { get }
    var currentSource: AudioSource? { get }
    var sampleRate: Double { get }
    var channelCount: Int { get }

    func listSources() async throws -> [AudioSource]
    func selectSource(_ source: AudioSource) async throws
    func start() async throws
    func stop() async
    func setAudioBufferHandler(_ handler: @escaping AudioBufferHandler)
}
