# macOS Audio Capture Notes

Spectra uses ScreenCaptureKit because it is the modern public API that can provide display-associated system audio output through `SCStream`.

## Version Requirement

- `SCStreamConfiguration.capturesAudio` is available on macOS 13 or newer.
- App and microphone audio output types vary by macOS release; the MVP only uses system audio output.
- Spectra explicitly reports unsupported OS state before trying to start system capture.

## Permission

ScreenCaptureKit capture is controlled by macOS privacy permissions. Users may see this as Screen Recording or Screen & System Audio Recording depending on OS version. This is not the Accessibility permission.

Spectra preflights `CGPreflightScreenCaptureAccess()` before enumerating system sources. If access is missing, it shows a permission message and keeps Test Signal Mode available.

For local SwiftPM development, use `Scripts/build-debug-app.sh` and launch `.build/Spectra.app` when validating permissions. Raw `swift run Spectra` is useful for quick renderer checks, but macOS may treat it as a command-line executable instead of a stable app identity in Privacy & Security.

## Fallback

If capture fails because permission is denied, there are no displays, or the API returns an unsupported format, Spectra starts Test Signal Mode.

## Format Handling

The MVP accepts linear PCM Float32, Int16, and Int32 buffers from ScreenCaptureKit and converts them to interleaved Float PCM for the shared analysis pipeline. Other formats are intentionally dropped until a converter is added.

## Troubleshooting

- Grant Screen & System Audio Recording permission.
- Relaunch or refresh sources after changing permission.
- Prefer System Mix if app-scoped capture does not expose the desired app.
- Verify visuals with Test Signal Mode before debugging system capture.

## Non-Goals For MVP

- No kernel extensions.
- No bundled virtual audio driver.
- No automatic audio recording.
- No upload or telemetry.
