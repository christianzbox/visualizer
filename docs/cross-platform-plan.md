# Cross-Platform Plan

## macOS

- Capture: ScreenCaptureKit `SCStream` with `capturesAudio`.
- Analysis: Accelerate/vDSP with adaptive normalization and shared `VisualAudioFrame` output.
- Rendering: Metal.
- Target: modern macOS on Apple Silicon.

## Windows

- Capture: WASAPI loopback capture for system mix.
- App/source capture: Windows audio session APIs where available.
- Rendering: DirectX or WGPU.

## Linux

- Capture: PipeWire preferred.
- Fallback: PulseAudio monitor sources.
- Rendering: WGPU or native OpenGL/Vulkan layer.

## Shared Model

All platforms should emit interleaved Float PCM `AudioBufferFrame` values into the shared analysis model and consume `VisualAudioFrame` from the preset/render layer. Backend-specific capture errors should map to user-facing unsupported, permission denied, source unavailable, and unsupported format states.

## Shell Options

Native apps should remain the performance baseline. Tauri, Electron, or another shell should be considered only if delivery speed outweighs native audio/rendering integration.

## Roadmap

- Keep `AudioCaptureEngine` as the backend boundary.
- Extract pure analysis/preset settings into a portable package if Windows/Linux work starts.
- Add a renderer abstraction only when a second renderer exists; avoid premature WGPU migration before capture quality is proven.
