import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spectra")
                .font(.largeTitle.weight(.semibold))
            Text("A local, system-wide audio visualizer for macOS.")
                .foregroundStyle(.secondary)
            Text("Audio analysis happens on this Mac. Spectra does not upload, record, or save audio by default.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
