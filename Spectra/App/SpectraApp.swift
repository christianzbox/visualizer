import SwiftUI

@main
struct SpectraApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    await appState.bootstrap()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Start Visualization") {
                    Task { await appState.startCapture() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Stop Visualization") {
                    Task { await appState.stopCapture() }
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
