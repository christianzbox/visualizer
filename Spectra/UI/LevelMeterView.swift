import SpectraCore
import SwiftUI

struct LevelMeterView: View {
    let frame: VisualAudioFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Level")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text(frame.isSilent ? "quiet" : "live")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(frame.isSilent ? .white.opacity(0.40) : .green.opacity(0.80))
            }

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

            HStack(spacing: 4) {
                miniBand(frame.smoothedBass, color: .cyan)
                miniBand(frame.midEnergy, color: .mint)
                miniBand(frame.trebleEnergy, color: .pink)
            }
            .frame(height: 4)

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

    private func miniBand(_ value: Float, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.70))
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, value))))
            }
        }
    }
}
