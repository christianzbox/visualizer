import SpectraCore
import SwiftUI

struct LevelMeterView: View {
    let frame: VisualAudioFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Level")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.11))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelGradient)
                        .frame(width: proxy.size.width * CGFloat(min(1, frame.smoothedVolume)))
                }
            }
            .frame(height: 10)

            HStack {
                Text("RMS \(frame.rms, specifier: "%.3f")")
                Spacer()
                Text("Peak \(frame.peak, specifier: "%.2f")")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [Color.cyan, Color.green, Color.yellow, Color.red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
