import SpectraCore
import SwiftUI

struct PresetShelfView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PresetCatalog.presets) { preset in
                    presetButton(preset)
                }
            }
            .padding(8)
        }
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func presetButton(_ preset: VisualPresetDescriptor) -> some View {
        let selected = preset.id == appState.selectedPreset
        return Button {
            appState.selectedPreset = preset.id
        } label: {
            HStack(spacing: 7) {
                Image(systemName: iconName(for: preset.id))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? .black : .white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.white.opacity(0.88) : Color.white.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.white.opacity(0.20) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(PresetCatalog.descriptor(for: preset.id).description)
    }

    private func iconName(for preset: VisualPresetID) -> String {
        switch preset {
        case .spectrumBars:
            return "chart.bar.fill"
        case .liquidWaveform:
            return "waveform"
        case .particleGalaxy:
            return "sparkles"
        case .neonTunnel:
            return "circle.hexagongrid.fill"
        case .minimalWaveform:
            return "waveform.path"
        case .mandelbrotBloom:
            return "circle.grid.cross"
        case .juliaVortex:
            return "hurricane"
        case .burningShip:
            return "flame.fill"
        case .tricornPulse:
            return "triangle.fill"
        case .phoenixField:
            return "point.3.connected.trianglepath.dotted"
        case .mandelboxFlight:
            return "cube.transparent"
        case .terrainFlight:
            return "mountain.2.fill"
        case .nebulaVoyage:
            return "sparkle.magnifyingglass"
        }
    }
}
