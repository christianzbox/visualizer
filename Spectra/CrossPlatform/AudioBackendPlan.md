# Audio Backend Plan

Spectra's capture API is intentionally backend-neutral. The current macOS implementation uses ScreenCaptureKit for system mix and application-scoped audio when permission is granted. Future platforms should conform to the same `AudioCaptureEngine` contract and emit interleaved Float PCM `AudioBufferFrame` values.

## macOS

- Primary backend: ScreenCaptureKit `SCStream` with `capturesAudio`.
- Renderer: Metal.
- Analysis: Accelerate/vDSP FFT on local buffers.
- Requirement: macOS 13 or newer for ScreenCaptureKit audio output. Newer macOS releases expose this to users as Screen & System Audio Recording permission.

## Windows

- Preferred backend: WASAPI loopback capture for default render endpoint.
- App-scoped capture can later use Windows audio session APIs where available.
- Renderer options: DirectX, Metal-equivalent abstraction, or WGPU.

## Linux

- Preferred backend: PipeWire stream capture.
- Fallback: PulseAudio monitor sources.
- App/source capture depends on compositor/session policy and should be surfaced as experimental.

## Shared Components

- `AudioBufferFrame`
- `AudioAnalysisEngine`
- FFT and frequency-band analysis
- `VisualAudioFrame`
- Preset descriptors and settings

## Shell Options

Native shells should remain preferred for low-latency capture and rendering. Tauri, Electron, or WGPU shells may be evaluated later if cross-platform delivery outweighs native integration.
