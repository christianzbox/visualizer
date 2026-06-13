import SwiftUI

@main
struct SpectraApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 500)
                .task {
                    await appState.bootstrap()
                    if CommandLine.arguments.contains("--start-capture") {
                        await appState.startCapture()
                    }
                }
        }
        .defaultSize(width: 1080, height: 700)
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
