# Linux PipeWire Capture Stub

Future backend target:

- Use PipeWire to capture monitor streams or application nodes when the session permits it.
- Fall back to PulseAudio monitor sources on older desktops.
- Convert captured buffers to interleaved Float PCM.
- Emit `AudioBufferFrame` through `AudioCaptureEngine`.
- Keep capture local and avoid recording by default.
