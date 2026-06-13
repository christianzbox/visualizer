# Spectra Architecture

Spectra is split into a reusable core target and a macOS executable target.

## Core

- `AudioCaptureEngine`: platform-neutral capture contract.
- `AudioBufferFrame`: interleaved Float PCM plus timestamp/source metadata.
- `TestSignalCaptureEngine`: deterministic local source for development, tests, and fallback.
- `MacSystemAudioCaptureEngine`: ScreenCaptureKit-backed macOS capture with runtime support checks, permission preflight, and fallback-friendly errors.
- `AudioAnalysisEngine`: mono conversion, ring-buffered FFT window, waveform, adaptive band normalization, onset, beat, smoothing, and sustained silence detection.
- `VisualAudioFrame`: renderer-facing schema.
- `PresetCatalog`: preset descriptors and settings.
- `MediaMetadataProvider`: optional metadata interface; visualization never depends on metadata.

## App

- `AppState`: owns settings, capture engine selection, analysis queue, UI frame throttling, and renderer handoff.
- `VisualFrameStore`: lock-protected latest-frame handoff from analysis to Metal.
- SwiftUI views: visual area, source/status, grouped preset picker, responsive controls, settings, debug overlay.
- `MetalRenderer`: builds geometry presets from the latest `VisualAudioFrame` using a reusable vertex array and grow-only Metal buffer. Fractal presets use a separate full-screen Metal fragment pipeline with shared audio uniforms.

## Threading

The capture callback only hands buffers to an analysis queue. Analysis produces `VisualAudioFrame` values off the main thread and updates a lock-protected frame store. UI is throttled to roughly 20 Hz. Metal reads the latest frame at display rate.

## Presets

- Spectrum Bars: smoothed logarithmic bands, bass glow, treble shimmer.
- Liquid Waveform: ribbon waveform with bass-driven fluid drift.
- Particle Galaxy: deterministic particle field with beat expansion and treble shimmer.
- Neon Tunnel: radial line tunnel with audio-reactive depth.
- Minimal Waveform: restrained low-density waveform for voice and background use.
- Mandelbrot Bloom: classic escape-time Mandelbrot formula with bass zoom, mid rotation, and treble color bands.
- Julia Vortex: Julia recurrence with an audio-driven complex seed.
- Burning Ship: rectified complex recurrence with low-frequency expansion.
- Tricorn Pulse: conjugate quadratic recurrence driven by mids and beat pressure.
- Phoenix Field: feedback recurrence with treble detail and bass expansion.

## Test Strategy

XCTest files live under `Tests/SpectraTests` and run in a full Xcode environment. The active Command Line Tools install on this machine lacks `XCTest`, so `swift test` is gated to compile cleanly and `SpectraDiagnostics` executes the local checks from a plain Swift executable.

GitHub Actions runs both paths on `macos-latest`: package tests for Xcode-backed XCTest coverage and `SpectraDiagnostics` for command-line-safe regression checks.
