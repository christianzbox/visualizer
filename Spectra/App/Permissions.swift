import CoreGraphics
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
    }

    static var systemAudioPermissionMessage: String {
        "Spectra needs Screen & System Audio Recording permission to visualize system audio. Audio stays local and is not recorded or uploaded."
    }
}
