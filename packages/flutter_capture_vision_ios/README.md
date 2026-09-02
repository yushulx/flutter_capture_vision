# flutter_capture_vision_ios

iOS implementation of [`flutter_capture_vision`](https://github.com/yushulx/flutter_capture_vision).

Endorsed `default_package` for the facade — you normally depend only on `flutter_capture_vision` and get this package automatically.

## Implementation notes

- Swift plugin bridging to the Dynamsoft Capture Vision CocoaPods bundle (`DynamsoftCaptureVisionBundle`).
- All SDK work is confined to a serial worker queue; results are delivered back on the main queue. License verification is asynchronous and completes the `initialize` call.
- Default task → template mapping: `barcode` → `ReadBarcodes_Default`, `mrz` → `ReadPassportAndId`, `documentDetection` → `DetectDocumentBoundaries_Default`. Custom template names from imported settings JSON are passed through unchanged.
- The podspec declares the minimum iOS version and required pods; models and parser resources arrive with the pod. No license key is embedded — pass it to `FlutterCaptureVision.initialize`.
- Verify on both device and simulator architectures before release.

See `example/` for a minimal app exercising this implementation.
