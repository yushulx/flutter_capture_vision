# flutter_capture_vision_platform_interface

Common platform interface, value types, and versioned channel contract for the `flutter_capture_vision` federated plugin.

End users should depend on `flutter_capture_vision` instead of this package. This package exists for platform implementers and for the pure Dart contracts:

- Value types: `VisionTask`, `VisionImageBuffer`, `VisionPixelFormat`, `VisionRotation`, `VisionPoint`, `VisionQuadrilateral`.
- Requests: `CaptureVisionRequest.forTasks` / `CaptureVisionRequest.namedTemplate` (mutually exclusive).
- Results: `CaptureVisionResult`, `BarcodeResult`, `MrzResult`, `DocumentDetectionResult` — always typed lists, never `null`.
- Templates: `CaptureVisionTemplate.parseAll(settingsJson)` extracts `CaptureVisionTemplates[].Name` with order and case preserved, rejecting missing, blank, non-string, or duplicate names.
- Errors: `CaptureVisionException(code, message, cause)`.
- Platform contract: `CaptureVisionPlatform` (all operations are `Future`-based) and the reference `MethodChannelCaptureVision` used by the native implementations.

See `example/` for a runnable tour of the contracts without any native SDK.
