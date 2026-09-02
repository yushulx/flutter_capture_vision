# flutter_capture_vision_windows

Windows implementation of [`flutter_capture_vision`](https://github.com/yushulx/flutter_capture_vision).

Endorsed `default_package` for the facade — you normally depend only on `flutter_capture_vision` and get this package automatically.

## Implementation notes

- C++ plugin over the DCV desktop SDK (`CCaptureVisionRouter`), with headers, libraries, and the full resource set (Templates, Models, ParserResources, root `.data` files) vendored into this package.
- All channel operations run on a dedicated serial worker thread; the method channel itself never blocks the UI thread.
- CMake copies the DLLs and resources next to the built executable, so a released app does not depend on a developer machine directory. Verify the bundle contains `*.dll`, `Templates/`, `Models/`, `ParserResources/`, and the root data files after `flutter build windows`.
- Default task → template mapping: `barcode` → `ReadBarcodes_Default`, `mrz` → `ReadPassportAndId`, `documentDetection` → `DetectDocumentBoundaries_Default`. Custom names from imported settings JSON are passed through unchanged.

See `example/` for a minimal app exercising this implementation.
