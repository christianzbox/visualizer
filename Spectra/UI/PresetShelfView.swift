import SpectraCore
import SwiftUI

struct PresetShelfView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.60))
                Text("Presets")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.64))
                Spacer()
                Text(PresetCatalog.descriptor(for: appState.selectedPreset).description)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(VisualPresetCategory.allCases) { category in
                        let presets = PresetCatalog.presets.filter { $0.category == category }
                        if !presets.isEmpty {
                            categoryGroup(category, presets: presets)
                        }
                    }
                }
                .padding(.bottom, 1)
            }
        }
        .padding(10)
        .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func categoryGroup(_ category: VisualPresetCategory, presets: [VisualPresetDescriptor]) -> some View {
        HStack(spacing: 7) {
            Text(category.label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(categoryTint(category).opacity(0.78))
                .fixedSize()

            ForEach(presets) { preset in
                presetButton(preset)
            }
        }
    }

    private func presetButton(_ preset: VisualPresetDescriptor) -> some View {
        let selected = preset.id == appState.selectedPreset
        let tint = categoryTint(preset.category)
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
                    .fill(selected ? tint.opacity(0.92) : Color.white.opacity(0.075))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.white.opacity(0.38) : tint.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(PresetCatalog.descriptor(for: preset.id).description)
    }

    private func categoryTint(_ category: VisualPresetCategory) -> Color {
        switch category {
        case .spectrum:
            return .cyan
        case .waveform:
            return .mint
        case .particles:
            return .orange
        case .ambient:
            return .purple
        case .fractal:
            return .pink
        case .journey:
            return .indigo
        }
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
        case .skyRealmFlight:
            return "cloud.sun.fill"
        case .crystalCavern:
            return "diamond.fill"
        case .forestCanopyFlight, .autumnForest, .bambooRain, .redwoodTrail, .rainforestTemple, .cherryBlossomValley:
            return "tree.fill"
        case .riverValleyFlight, .glacialFjord, .coastalCliffs, .moonlitMarsh, .islandArchipelago, .riverCity, .oldTownCanals, .cyberHarbor:
            return "water.waves"
        case .alpinePass, .stormRidge, .tundraLights, .auroraPeaks:
            return "mountain.2.fill"
        case .desertDunes, .canyonRun, .volcanicBadlands, .savannaSunset, .desertCity, .crystalMesa:
            return "sun.max.fill"
        case .neonCityFlyover, .rainCity, .sunsetSkyline, .megaCityGrid, .rooftopChase, .industrialDocks, .spaceportDawn:
            return "building.2.fill"
        case .mountainCitadel, .floatingCity, .snowVillage, .templeRuins:
            return "building.columns.fill"
        }
    }
}
