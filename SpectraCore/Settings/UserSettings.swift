import Foundation

public struct UserSettings: Codable, Equatable, Sendable {
    public var selectedPreset: VisualPresetID
    public var presetSettings: PresetSettings
    public var captureMode: CaptureMode
    public var selectedSourceId: String?
    public var launchFullScreen: Bool
    public var alwaysOnTop: Bool
    public var showDebugOverlay: Bool
    public var reduceMotion: Bool
    public var testSignalType: TestSignalType
    public var privacyAcknowledged: Bool

    public init(
        selectedPreset: VisualPresetID = .spectrumBars,
        presetSettings: PresetSettings = .default,
        captureMode: CaptureMode = .testSignal,
        selectedSourceId: String? = nil,
        launchFullScreen: Bool = false,
        alwaysOnTop: Bool = false,
        showDebugOverlay: Bool = false,
        reduceMotion: Bool = false,
        testSignalType: TestSignalType = .beatPattern,
        privacyAcknowledged: Bool = false
    ) {
        self.selectedPreset = selectedPreset
        self.presetSettings = presetSettings
        self.captureMode = captureMode
        self.selectedSourceId = selectedSourceId
        self.launchFullScreen = launchFullScreen
        self.alwaysOnTop = alwaysOnTop
        self.showDebugOverlay = showDebugOverlay
        self.reduceMotion = reduceMotion
        self.testSignalType = testSignalType
        self.privacyAcknowledged = privacyAcknowledged
    }

    public static let `default` = UserSettings()
}
