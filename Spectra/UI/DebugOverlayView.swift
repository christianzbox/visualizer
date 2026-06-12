import SwiftUI

struct DebugOverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("FPS \(appState.framesPerSecond, specifier: "%.0f")")
            Text("RMS \(appState.latestFrame.rms, specifier: "%.3f")")
            Text("Peak \(appState.latestFrame.peak, specifier: "%.3f")")
            Text("Bass \(appState.latestFrame.bassEnergy, specifier: "%.2f")")
            Text("Mid \(appState.latestFrame.midEnergy, specifier: "%.2f")")
            Text("Treble \(appState.latestFrame.trebleEnergy, specifier: "%.2f")")
            Text(appState.currentSource?.name ?? "No Source")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.78))
        .padding(10)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }
}
