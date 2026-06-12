# Windows WASAPI Loopback Capture Stub

Future backend target:

- Enumerate render endpoints with MMDevice API.
- Use WASAPI loopback capture on the selected endpoint.
- Convert captured buffers to interleaved Float PCM.
- Emit `AudioBufferFrame` through `AudioCaptureEngine`.
- Keep capture local and avoid recording by default.
