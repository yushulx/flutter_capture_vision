# flutter_capture_vision_macos

macOS implementation of [`flutter_capture_vision`](https://github.com/yushulx/flutter_capture_vision).

Endorsed `default_package` for the facade — you normally depend only on `flutter_capture_vision` and get this package automatically.

## Implementation notes

- Objective-C++ plugin over the DCV desktop SDK (`CCaptureVisionRouter`); dylibs and the full resource set (Templates, Models, ParserResources, root `.data` files) are vendored into this package and copied into the app bundle where the SDK can find them — not into a buried resource bundle.
- All channel operations run on a serial GCD worker queue; the method channel returns immediately and replies asynchronously on the main queue.
- Before release, verify `codesign --verify` on the built app, that rpaths resolve (`otool -L`), and that notarization covers the bundled dylibs.
- Default task → template mapping: `barcode` → `ReadBarcodes_Default`, `mrz` → `ReadPassportAndId`, `documentDetection` → `DetectDocumentBoundaries_Default`. Custom names from imported settings JSON are passed through unchanged.

See `example/` for a minimal app exercising this implementation.
