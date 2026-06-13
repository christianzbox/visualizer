import SpectraCore
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            MetalVisualizerView(appState: appState)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.38), .clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

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
        .background(.black)
    }

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            regularTopBar
            compactTopBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var regularTopBar: some View {
        HStack(spacing: 12) {
            brandText
            statusText
            Spacer()
            privacyBadge
        }
    }

    private var compactTopBar: some View {
        HStack(spacing: 10) {
            brandText
            statusText
                .minimumScaleFactor(0.72)
            Spacer(minLength: 8)
        }
    }

    private var brandText: some View {
        Text("Spectra")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    private var statusText: some View {
        Text(appState.statusMessage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var privacyBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text("Local audio analysis")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.74))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.34), in: Capsule())
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
