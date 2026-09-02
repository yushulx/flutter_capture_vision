# flutter_capture_vision_android

Android implementation of [`flutter_capture_vision`](https://github.com/yushulx/flutter_capture_vision).

Endorsed `default_package` for the facade — you normally depend only on `flutter_capture_vision` and get this package automatically.

## Implementation notes

- Java plugin bridging to the Dynamsoft Capture Vision Android AAR.
- Every method-channel operation (license, `initSettings`/`resetSettings`, file and raw-buffer capture, dispose) runs on a single background executor and replies on the main thread, so captures never block the platform thread or race template state.
- Default task → template mapping: `barcode` → `ReadBarcodes_Default`, `mrz` → `ReadPassportAndId`, `documentDetection` → `DetectDocumentBoundaries_Default`. Custom names from imported settings JSON are passed through unchanged.
- MRZ models, barcode models, and document-detection resources ship with the DCV dependency; verify `minSdk` and ABI coverage in your app, and keep model resources intact when enabling shrinking (`shrinkResources` / R8).

See `example/` for a minimal app exercising this implementation.
