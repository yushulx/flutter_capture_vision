# flutter_capture_vision_linux

Linux implementation of [`flutter_capture_vision`](https://github.com/yushulx/flutter_capture_vision).

Endorsed `default_package` for the facade — you normally depend only on `flutter_capture_vision` and get this package automatically.

## Implementation notes

- C++ plugin over the DCV desktop SDK (`CCaptureVisionRouter`), with x64 and arm64 libraries plus the full resource set (Templates, Models, ParserResources, root `.data` files) vendored into this package.
- All channel operations run on a dedicated serial worker thread; replies are posted back through the main GLib context.
- CMake selects the library matching the target architecture, installs everything under the bundle's `lib/` with `$ORIGIN` rpath, and installs the resource directories next to the executable. After `flutter build linux`, verify with `ldd` that bundled libraries resolve from the bundle.
- Default task → template mapping: `barcode` → `ReadBarcodes_Default`, `mrz` → `ReadPassportAndId`, `documentDetection` → `DetectDocumentBoundaries_Default`. Custom names from imported settings JSON are passed through unchanged.
- This package carries both architectures; if pub archive size ever exceeds the pub.dev limit, split per-architecture rather than downloading resources at runtime (see `docs/release-runbook.md` in the workspace).

See `example/` for a minimal app exercising this implementation.
