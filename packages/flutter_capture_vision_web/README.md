# flutter_capture_vision_web

Web implementation of [`flutter_capture_vision`](https://github.com/yushulx/flutter_capture_vision).

Endorsed `default_package` for the facade — you normally depend only on `flutter_capture_vision` and get this package automatically.

## Implementation notes

- Dart `js_interop` adapter over the Dynamsoft DCV browser bundle. DCV's Promise-based API is awaited directly; nothing runs synchronously on the UI thread.
- The JS/WASM/worker/model bundle is self-hosted under `assets/dcv/` and loaded by the plugin — apps must **not** add a CDN `<script>` tag to `web/index.html`. The adapter sets the engine `rootDirectory` to the packaged assets before initialization.
- Requires HTTPS or `localhost` (WASM constraint).
- Default task → template mapping: `barcode` → `ReadBarcodes_Default`, `mrz` → `ReadPassportAndId`, `documentDetection` → `DetectDocumentBoundaries_Default`. Custom names from imported settings JSON are passed through unchanged.

See `example/` for a minimal app exercising this implementation.
