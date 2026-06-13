import MetalKit
import SpectraCore
import SwiftUI

struct MetalVisualizerView: NSViewRepresentable {
    @ObservedObject var appState: AppState

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(
            frameStore: appState.frameStore,
            presetProvider: { appState.selectedPreset },
            settingsProvider: { appState.renderSettings },
            fpsHandler: { fps in
                DispatchQueue.main.async {
                    appState.updateFramesPerSecond(fps)
                }
            }
        )
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(
            presetProvider: { appState.selectedPreset },
            settingsProvider: { appState.renderSettings }
        )
    }
}
