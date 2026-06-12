import SwiftUI

struct PermissionView: View {
    let requestAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 42))
                .foregroundStyle(.cyan)
            Text("Spectra needs audio-capture permission to visualize system audio. Audio stays local and is not recorded or uploaded.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Open Permission Prompt", action: requestAction)
        }
        .padding(28)
    }
}
