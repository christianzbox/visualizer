# Spectra

Spectra is a macOS system-audio visualizer. It analyzes live audio locally and renders reactive Metal visuals for whatever the Mac is playing: music apps, browsers, games, calls, videos, podcasts, and system sounds when macOS grants capture permission.

## Current MVP

- SwiftUI macOS shell.
- Metal-backed visualizer view.
- Ten working presets: Spectrum Bars, Liquid Waveform, Particle Galaxy, Neon Tunnel, Minimal Waveform, plus five true iterative fractal presets.
- Cinematic render layers: ambient wash, reflections, waveform veils, galaxy arms, tunnel rays, fractal filaments, and transient sparkle mapped to real audio features.
- Test Signal Mode with sine, bass pulse, noise, and fake beat pattern.
- Accelerate/vDSP FFT analysis with adaptive band normalization, onset/beat detection, smoothing, silence detection, and level metering.
- ScreenCaptureKit system mix and experimental app-source capture backend.
- Optional metadata architecture with current source app and lazy Apple Music track lookup.
- Local-only privacy model. No telemetry, network calls, upload, recording, or saved audio.

## Requirements

- macOS 13 or newer for ScreenCaptureKit system audio capture.
- Apple Silicon recommended.
- Xcode can open `Package.swift`. This repository currently builds with Swift Package Manager.
- The active Command Line Tools are enough for `swift build`, `swift test`, and `swift run SpectraDiagnostics`; a full Xcode install is needed for `xcodebuild` workflows.

## Build And Run

```bash
swift build
swift build -c release
swift run Spectra
```

Open in Xcode:

```bash
open Package.swift
```

Run package tests and diagnostics:

```bash
swift test
swift run SpectraDiagnostics
```

This machine's active Command Line Tools do not include `XCTest`, so the XCTest files are gated with `#if canImport(XCTest)`. `swift test` verifies the test target compiles under CLT; `SpectraDiagnostics` executes the core FFT, band mapping, silence, beat, smoothing, test signal, and settings persistence checks. In full Xcode, the XCTest files are available normally.

## Permissions

System audio capture uses ScreenCaptureKit. On modern macOS this is controlled by Screen & System Audio Recording permission. Spectra preflights permission before enumerating system sources, shows a clear recovery message, and falls back to Test Signal Mode when permission is denied, unsupported, or unavailable.

Privacy text shown by the app:

> Spectra analyzes live audio locally to drive visuals. It does not upload, record, or save your audio by default.

## Usage

1. Launch Spectra.
2. Test Signal Mode starts by default, so visuals should react immediately.
3. Switch Capture Mode to System Mix to capture Mac output.
4. Grant Screen & System Audio Recording permission if macOS prompts, then refresh sources.
5. Play audio in any app.
6. Switch between Spectrum Bars, Liquid Waveform, Particle Galaxy, Neon Tunnel, Minimal Waveform, and the fractal family.
7. Fractal choices are real formulas: Mandelbrot, Julia, Burning Ship, Tricorn, and Phoenix.
8. Use the full-screen button or standard macOS full-screen controls.
9. Adjust sensitivity, intensity, palette, motion, glow, and beat response, or pin the window as floating.

## Troubleshooting

- If System Mix does not start, use the in-app permission prompt or open System Settings and grant Screen & System Audio Recording to Spectra.
- If permission was just changed, quit and relaunch Spectra or refresh sources.
- If no real audio is captured, switch to Test Signal Mode to verify the renderer and analysis pipeline.
- If an app source disappears, refresh sources and select System Mix.
- If running from SwiftPM does not present the final app identity expected by macOS privacy settings, use a signed Xcode app target for capture validation.

## GitHub Build Checks

This repository includes `.github/workflows/ci.yml`. The workflow runs on pushes to `main`, pushes to `codex/**` branches, pull requests targeting `main`, and manual dispatch.

The CI job runs:

- `swift package resolve`
- `swift build`
- `swift build -c release`
- `swift test`
- `swift run SpectraDiagnostics`
- `swift package describe`

To make CI required in GitHub:

1. Push this branch.
2. Open a pull request into `main`.
3. Go to repository Settings -> Actions -> General and confirm Actions are enabled.
4. Go to Settings -> Branches -> Add branch protection rule.
5. Set branch name pattern to `main`.
6. Enable `Require status checks to pass before merging`.
7. Select the `Build and Test` status check after it has run at least once.
8. Enable `Require branches to be up to date before merging`.
9. Optionally enable `Require a pull request before merging`.
10. Save the rule.

## Manual QA Checklist

1. Launch app.
2. Enable Test Signal Mode.
3. Verify visuals react.
4. Play Apple Music.
5. Verify system audio capture reacts.
6. Play YouTube in a browser.
7. Verify visualizer reacts.
8. Switch presets.
9. Try each fractal preset and verify different structure, not only color changes.
10. Resize the window narrower and verify controls collapse instead of clipping.
11. Go full-screen.
12. Toggle floating window mode.
13. Stop audio and verify visuals settle after the silence hold.
14. Deny permission and verify friendly error/fallback behavior.
15. Quit and relaunch; settings persist.
16. Run `swift run SpectraDiagnostics`.

## Known Limitations

- Menu bar status item is not implemented yet. Basic commands are available from the app menu.
- External display selection is not implemented as a dedicated picker; use normal macOS window movement/full-screen behavior for now.
- ScreenCaptureKit app-source capture is experimental and depends on macOS permission behavior.
- `Config/Spectra-Info.plist` contains distribution privacy strings, but a signed `.app` bundle/Xcode project should promote these into bundle settings before distribution.
- Apple Music metadata uses Apple Events when explicitly queried by future UI and is not required for visualization.
- The SwiftPM renderer compiles its Metal shader at runtime for package reliability; a production Xcode target should compile `Shaders.metal`.

## Roadmap

- Signed Xcode app target with explicit bundle identifiers, privacy strings, and hardened runtime settings.
- Menu bar status item and external-display routing.
- More capture diagnostics for stream format errors and source changes.
- Optional metadata UI with Apple Music/Spotify providers.
- GPU-side particle simulation once visual complexity grows.

## Recommended Next Engineering Step

Create a signed Xcode app target around the package sources, wire `Config/Spectra-Info.plist` into bundle settings, and validate Screen & System Audio Recording behavior on macOS 14, 15, and 26.
