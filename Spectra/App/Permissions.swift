import CoreGraphics
import AppKit
import Foundation

enum PermissionStatus: String {
    case authorized
    case notDeterminedOrDenied
}

enum Permissions {
    static var screenCaptureStatus: PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .notDeterminedOrDenied
    }

    static func requestScreenCaptureAccess() {
        _ = CGRequestScreenCaptureAccess()
        openScreenCaptureSettings()
    }

    static var systemAudioPermissionMessage: String {
        "Spectra needs Screen & System Audio Recording permission to visualize system audio. Audio stays local and is not recorded or uploaded."
    }

    static func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
