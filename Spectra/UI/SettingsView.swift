import SpectraCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Mode", selection: Binding(
                    get: { appState.captureMode },
                    set: { appState.captureMode = $0 }
                )) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if appState.captureMode == .testSignal {
                    Picker("Test Signal", selection: Binding(
                        get: { appState.testSignalType },
                        set: { appState.testSignalType = $0 }
                    )) {
                        ForEach(TestSignalType.allCases, id: \.self) { signal in
                            Text(signal.label).tag(signal)
                        }
                    }
                }

                Button("Open Recording Privacy Settings") {
                    appState.requestSystemCapturePermission()
                }
            }

            Section("Visuals") {
                Picker("Preset", selection: Binding(
                    get: { appState.selectedPreset },
                    set: { appState.selectedPreset = $0 }
                )) {
                    ForEach(VisualPresetCategory.allCases) { category in
                        Section(category.label) {
                            ForEach(PresetCatalog.presets.filter { $0.category == category }) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                    }
                }

                Picker("Palette", selection: Binding(
                    get: { appState.presetSettings.palette },
                    set: {
                        var settings = appState.presetSettings
                        settings.palette = $0
                        appState.presetSettings = settings
                    }
                )) {
                    ForEach(ColorPalette.allCases) { palette in
                        Text(palette.label).tag(palette)
                    }
                }

                Toggle("Reduce Motion", isOn: Binding(
                    get: { appState.settings.reduceMotion },
                    set: { value in
                        appState.updateSettings { $0.reduceMotion = value }
                    }
                ))

                Slider(value: presetSettingBinding(\.sensitivity), in: 0...1) {
                    Text("Sensitivity")
                }

                Slider(value: presetSettingBinding(\.intensity), in: 0...1) {
                    Text("Intensity")
                }

                Slider(value: presetSettingBinding(\.motionAmount), in: 0...1) {
                    Text("Motion")
                }

                Slider(value: presetSettingBinding(\.glowAmount), in: 0...1) {
                    Text("Glow")
                }

                Slider(value: presetSettingBinding(\.beatReactivity), in: 0...1) {
                    Text("Beat Response")
                }

                Toggle("Show Debug Overlay", isOn: Binding(
                    get: { appState.settings.showDebugOverlay },
                    set: { value in
                        appState.updateSettings { $0.showDebugOverlay = value }
                    }
                ))
            }

            Section("Window") {
                Toggle("Always On Top", isOn: Binding(
                    get: { appState.settings.alwaysOnTop },
                    set: { value in
                        appState.updateSettings { $0.alwaysOnTop = value }
                    }
                ))
                Toggle("Launch Full Screen", isOn: Binding(
                    get: { appState.settings.launchFullScreen },
                    set: { value in
                        appState.updateSettings { $0.launchFullScreen = value }
                    }
                ))
            }

            Section("Privacy") {
                Text("Spectra analyzes live audio locally to drive visuals. It does not upload, record, or save your audio by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func presetSettingBinding(_ keyPath: WritableKeyPath<PresetSettings, Double>) -> Binding<Double> {
        Binding(
            get: { appState.presetSettings[keyPath: keyPath] },
            set: { value in
                var settings = appState.presetSettings
                settings[keyPath: keyPath] = value
                appState.presetSettings = settings
            }
        )
    }
}
