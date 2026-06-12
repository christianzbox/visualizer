import SpectraCore
import SwiftUI

struct AudioSourceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isCapturing ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(appState.currentSource?.name ?? "No Source")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Picker("Mode", selection: Binding(
                    get: { appState.captureMode },
                    set: { mode in
                        appState.captureMode = mode
                        Task { await appState.startCapture() }
                    }
                )) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button {
                    Task { await appState.refreshSources() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Sources")
            }

            if appState.captureMode == .testSignal {
                Picker("Signal", selection: Binding(
                    get: { appState.testSignalType },
                    set: { appState.testSignalType = $0 }
                )) {
                    ForEach(TestSignalType.allCases, id: \.self) { signal in
                        Text(signal.label).tag(signal)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else if appState.captureMode == .application {
                Picker("Application", selection: Binding(
                    get: { appState.currentSource?.id ?? "" },
                    set: { sourceId in
                        guard let source = appState.availableSources.first(where: { $0.id == sourceId }) else { return }
                        appState.currentSource = source
                        appState.settings.selectedSourceId = source.id
                        Task { await appState.startCapture() }
                    }
                )) {
                    ForEach(appState.availableSources.filter { $0.kind == .application }) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
