# Privacy

Spectra's privacy model is local-first:

- Audio is analyzed locally on the Mac.
- Audio is not uploaded.
- Audio is not recorded or saved by default.
- Audio is not sent to analytics.
- The app contains no telemetry.
- The app contains no crash reporting.
- Test Signal Mode generates synthetic audio locally.
- Optional Apple Music metadata lookup is lazy and not required for visualization.
- Metadata does not include audio buffers and is not uploaded.

System audio capture requires macOS permission through ScreenCaptureKit. If permission is unavailable, Spectra keeps working with Test Signal Mode.

## Permission Copy

Spectra should tell users:

> Spectra analyzes live audio locally to drive visuals. It does not upload, record, or save your audio by default.

## Distribution Note

`Config/Spectra-Info.plist` contains the privacy usage strings expected in a signed app bundle. SwiftPM command-line launches are useful for development but are not a substitute for validating macOS privacy prompts in a signed app target.
