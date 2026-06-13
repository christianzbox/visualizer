import SpectraCore
import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularControls
            compactControls
        }
        .padding(14)
        .background(controlBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var controlBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                .black.opacity(0.62),
                .black.opacity(0.48),
                .white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var regularControls: some View {
        HStack(spacing: 16) {
            AudioSourceView()
                .frame(width: 260, alignment: .leading)

            LevelMeterView(frame: appState.latestFrame)
                .frame(width: 132)

            sliderStack
            .frame(width: 220)

            transportButtons
        }
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AudioSourceView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                transportButtons
            }

            HStack(spacing: 14) {
                LevelMeterView(frame: appState.latestFrame)
                    .frame(width: 132)
            }

            sliderStack
        }
    }

    private var sliderStack: some View {
        VStack(spacing: 8) {
            labeledSlider(
                title: "Sensitivity",
                value: Binding(
                    get: { appState.presetSettings.sensitivity },
                    set: {
                        var settings = appState.presetSettings
                        settings.sensitivity = $0
                        appState.presetSettings = settings
                    }
                )
            )
            labeledSlider(
                title: "Intensity",
                value: Binding(
                    get: { appState.presetSettings.intensity },
                    set: {
                        var settings = appState.presetSettings
                        settings.intensity = $0
                        appState.presetSettings = settings
                    }
                )
            )
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    appState.isCapturing ? await appState.stopCapture() : await appState.startCapture()
                }
            } label: {
                Image(systemName: appState.isCapturing ? "stop.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .help(appState.isCapturing ? "Stop Visualization" : "Start Visualization")

            Button {
                appState.toggleFullScreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 18, height: 18)
            }
            .help("Toggle Full Screen")

            Button {
                appState.toggleAlwaysOnTop()
            } label: {
                Image(systemName: appState.settings.alwaysOnTop ? "pin.fill" : "pin")
                    .frame(width: 18, height: 18)
            }
            .help("Toggle Floating Window")
        }
    }

    private func labeledSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Slider(value: value, in: 0...1)
                .controlSize(.small)
        }
    }
}
