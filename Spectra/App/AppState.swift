import AppKit
import Combine
import Foundation
import OSLog
import SpectraCore

@MainActor
final class AppState: ObservableObject {
    @Published var latestFrame: VisualAudioFrame = .silent
    @Published var isCapturing = false
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var availableSources: [AudioSource] = []
    @Published var currentSource: AudioSource?
    @Published var recordingPermissionStatus: PermissionStatus = Permissions.screenCaptureStatus
    @Published var settings: UserSettings {
        didSet {
            testSignalEngine.signalType = settings.testSignalType
            settingsStore.save(settings)
            updateWindowLevel()
        }
    }
    @Published var framesPerSecond: Double = 0

    let frameStore: VisualFrameStore

    private let logger = Logger(subsystem: "com.christianzbox.spectra", category: "capture")
    private let settingsStore = SettingsStore()
    private let pipeline: AudioProcessingPipeline
    private let testSignalEngine: TestSignalCaptureEngine
    private let systemAudioEngine = MacSystemAudioCaptureEngine()
    private var activeEngine: AudioCaptureEngine?

    init() {
        let loaded = settingsStore.load()
        let frameStore = VisualFrameStore()
        self.settings = loaded
        self.frameStore = frameStore
        self.pipeline = AudioProcessingPipeline(frameStore: frameStore)
        self.testSignalEngine = TestSignalCaptureEngine(signalType: loaded.testSignalType)
        self.pipeline.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.latestFrame = frame
            }
        }
    }

    var selectedPreset: VisualPresetID {
        get { settings.selectedPreset }
        set {
            guard settings.selectedPreset != newValue else { return }
            updateSettings {
                $0.selectedPreset = newValue
                $0.presetSettings = PresetCatalog.descriptor(for: newValue).defaultSettings
            }
        }
    }

    var presetSettings: PresetSettings {
        get { settings.presetSettings }
        set { updateSettings { $0.presetSettings = newValue } }
    }

    var renderSettings: PresetSettings {
        var output = settings.presetSettings
        output.reduceMotion = settings.reduceMotion
        return output
    }

    var captureMode: CaptureMode {
        get { settings.captureMode }
        set {
            updateSettings { $0.captureMode = newValue }
            if newValue == .testSignal {
                currentSource = AudioSource(id: "test-signal", name: "Test Signal", kind: .testSignal)
            }
        }
    }

    var testSignalType: TestSignalType {
        get { settings.testSignalType }
        set {
            updateSettings { $0.testSignalType = newValue }
            testSignalEngine.signalType = newValue
        }
    }

    func updateSettings(_ update: (inout UserSettings) -> Void) {
        var next = settings
        update(&next)
        settings = next
    }

    func selectSource(_ source: AudioSource) {
        currentSource = source
        updateSettings { settings in
            settings.selectedSourceId = source.id
            if source.kind == .application {
                settings.captureMode = .application
            } else if source.kind == .systemMix {
                settings.captureMode = .systemMix
            } else if source.kind == .testSignal {
                settings.captureMode = .testSignal
            }
        }
    }

    func bootstrap() async {
        ensureForegroundPresentation()
        refreshPermissionStatus()
        updateWindowLevel()
        if settings.launchFullScreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.toggleFullScreen()
            }
        }
        await refreshSources()
        if settings.captureMode == .testSignal {
            await startCapture()
        }
    }

    private func ensureForegroundPresentation() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func refreshSources() async {
        refreshPermissionStatus()
        var sources: [AudioSource] = []
        if let testSource = try? await testSignalEngine.listSources().first {
            sources.append(testSource)
        }
        do {
            sources.append(contentsOf: try await systemAudioEngine.listSources())
            recordingPermissionStatus = .authorized
            logger.info("Refreshed capture sources: \(sources.count, privacy: .public)")
            errorMessage = nil
        } catch {
            if (error as? AudioCaptureError) == .permissionDenied {
                recordingPermissionStatus = .notDeterminedOrDenied
            }
            let message = formatCaptureError(error)
            logger.error("Capture source refresh failed: \(message, privacy: .public)")
            errorMessage = message
        }
        availableSources = sources
        currentSource = sourceForCurrentSettings(from: sources)
    }

    func startCapture() async {
        await startCapture(retainedError: nil)
    }

    private func startCapture(retainedError: String?) async {
        await stopCapture()
        pipeline.reset()
        errorMessage = retainedError

        let engine: AudioCaptureEngine
        switch settings.captureMode {
        case .testSignal:
            engine = testSignalEngine
        case .systemMix, .application:
            engine = systemAudioEngine
        }

        do {
            if let source = sourceForCurrentSettings(from: availableSources) {
                try await engine.selectSource(source)
                currentSource = source
            }
            let pipeline = self.pipeline
            engine.setAudioBufferHandler { frame in
                pipeline.consume(frame)
            }
            try await engine.start()
            activeEngine = engine
            isCapturing = true
            if settings.captureMode != .testSignal {
                recordingPermissionStatus = .authorized
            }
            statusMessage = "Listening to \(engine.currentSource?.name ?? "audio")"
            logger.info("Started capture mode=\(self.settings.captureMode.rawValue, privacy: .public) source=\(engine.currentSource?.name ?? "audio", privacy: .public)")
        } catch {
            isCapturing = false
            activeEngine = nil
            let message = formatCaptureError(error)
            logger.error("Capture start failed: \(message, privacy: .public)")
            errorMessage = message
            statusMessage = "Capture unavailable"
            if settings.captureMode != .testSignal {
                statusMessage = "Using Test Signal fallback"
                captureMode = .testSignal
                await startCapture(retainedError: message)
            }
        }
    }

    func stopCapture() async {
        if let activeEngine {
            await activeEngine.stop()
        }
        activeEngine = nil
        isCapturing = false
        statusMessage = "Stopped"
    }

    func requestSystemCapturePermission() {
        Permissions.requestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshPermissionStatus()
        }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func toggleAlwaysOnTop() {
        updateSettings { $0.alwaysOnTop.toggle() }
    }

    func updateFramesPerSecond(_ fps: Double) {
        framesPerSecond = fps
    }

    func refreshPermissionStatus() {
        recordingPermissionStatus = Permissions.screenCaptureStatus
    }

    private func sourceForCurrentSettings(from sources: [AudioSource]) -> AudioSource? {
        if settings.captureMode == .testSignal {
            return sources.first { $0.kind == .testSignal }
        }
        if settings.captureMode == .systemMix {
            return sources.first { $0.kind == .systemMix }
        }
        if let id = settings.selectedSourceId {
            return sources.first { $0.id == id }
        }
        return sources.first { $0.kind == .application } ?? sources.first { $0.kind == .systemMix }
    }

    private func updateWindowLevel() {
        NSApp.windows.forEach { window in
            window.level = settings.alwaysOnTop ? .floating : .normal
        }
    }

    private func formatCaptureError(_ error: Error) -> String {
        guard let captureError = error as? AudioCaptureError else {
            return "\(error.localizedDescription) Test Signal Mode remains available."
        }
        let parts = [
            captureError.errorDescription,
            captureError.failureReason,
            captureError.recoverySuggestion
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }
}

final class AudioProcessingPipeline {
    var onFrame: ((VisualAudioFrame) -> Void)?

    private let analysisEngine = AudioAnalysisEngine()
    private let analysisQueue = DispatchQueue(label: "spectra.analysis", qos: .userInteractive)
    private let frameStore: VisualFrameStore
    private var lastUIPublish: TimeInterval = 0
    private var pendingFrame: AudioBufferFrame?
    private var isProcessing = false

    init(frameStore: VisualFrameStore) {
        self.frameStore = frameStore
    }

    func reset() {
        analysisQueue.sync {
            analysisEngine.reset()
            frameStore.update(.silent)
            lastUIPublish = 0
            pendingFrame = nil
            isProcessing = false
        }
    }

    func consume(_ frame: AudioBufferFrame) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.pendingFrame = frame
            guard !self.isProcessing else { return }
            self.isProcessing = true

            while let frame = self.pendingFrame {
                self.pendingFrame = nil
                let visualFrame = self.analysisEngine.process(frame)
                self.frameStore.update(visualFrame)

                let now = CACurrentMediaTime()
                if now - self.lastUIPublish > 1.0 / 20.0 {
                    self.lastUIPublish = now
                    DispatchQueue.main.async {
                        self.onFrame?(visualFrame)
                    }
                }
            }

            self.isProcessing = false
        }
    }
}

final class VisualFrameStore {
    private let lock = NSLock()
    private var frame: VisualAudioFrame = .silent

    func update(_ frame: VisualAudioFrame) {
        lock.lock()
        self.frame = frame
        lock.unlock()
    }

    func read() -> VisualAudioFrame {
        lock.lock()
        let output = frame
        lock.unlock()
        return output
    }
}
