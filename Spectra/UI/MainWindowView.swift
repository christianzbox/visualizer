import SpectraCore
import SwiftUI

struct MainWindowView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            MetalVisualizerView(appState: appState)
                .ignoresSafeArea()

            visualChrome

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let errorMessage = appState.errorMessage {
                    captureIssueState(errorMessage)
                } else if appState.latestFrame.isSilent && appState.isCapturing {
                    noAudioState
                }
                Spacer()
                PresetShelfView()
                    .frame(maxWidth: 1040)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                ControlPanelView()
                    .frame(maxWidth: 1040)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }

            if appState.settings.showDebugOverlay {
                DebugOverlayView()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520, height: 520)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    appState.toggleFullScreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Toggle Full Screen")

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            appState.refreshPermissionStatus()
            Task { await appState.refreshSources() }
        }
        .background(.black)
    }

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            regularTopBar
            compactTopBar
        }
        .frame(maxWidth: 1040)
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var regularTopBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                brandText
                statusText
            }
            Spacer()
            currentPresetBadge
            privacyBadge
        }
        .padding(12)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var compactTopBar: some View {
        HStack(spacing: 10) {
            brandText
            statusText
                .minimumScaleFactor(0.72)
            Spacer(minLength: 8)
            privacyIcon
        }
        .padding(12)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var brandText: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.cyan)
            Text("Spectra")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private var statusText: some View {
        Text(appState.statusMessage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var privacyBadge: some View {
        Button {
            if appState.recordingPermissionStatus == .authorized {
                appState.refreshPermissionStatus()
            } else {
                appState.requestSystemCapturePermission()
            }
        } label: {
            HStack(spacing: 6) {
                privacyIcon
                Text(appState.recordingPermissionStatus == .authorized ? "Recording access on" : "Recording access needed")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(permissionTint.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(permissionTint.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(appState.recordingPermissionStatus == .authorized ? "Recording permission is granted" : "Open Screen & System Audio Recording privacy settings")
    }

    private var privacyIcon: some View {
        Image(systemName: appState.recordingPermissionStatus == .authorized ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            .foregroundStyle(permissionTint)
    }

    private var permissionTint: Color {
        appState.recordingPermissionStatus == .authorized ? .green : .yellow
    }

    private var currentPresetBadge: some View {
        let preset = PresetCatalog.descriptor(for: appState.selectedPreset)
        return HStack(spacing: 6) {
            Text(preset.category.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.54))
            Text(preset.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var visualChrome: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.50), .clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.cyan.opacity(0.10), .clear, .pink.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .allowsHitTesting(false)
    }

    private var noAudioState: some View {
        Text("No audio detected. Play something on your Mac or use Test Signal Mode.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private func captureIssueState(_ message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    appState.requestSystemCapturePermission()
                } label: {
                    Label("Open Recording Privacy Settings", systemImage: "lock.open")
                }

                Button {
                    Task { await appState.refreshSources() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .frame(maxWidth: 620)
        .padding(18)
        .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }
}
