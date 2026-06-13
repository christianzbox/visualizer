import SpectraCore
import SwiftUI

struct PresetPickerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))

            Picker("Preset", selection: Binding(
                get: { appState.selectedPreset },
                set: { appState.selectedPreset = $0 }
            )) {
                ForEach(VisualPresetCategory.allCases) { category in
                    Section(category.label) {
                        ForEach(PresetCatalog.presets.filter { $0.category == category }) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}
