# flutter_capture_vision_example

The full six-platform example for [`flutter_capture_vision`](../). It drives all three Capture Vision tasks from one screen:

| Mode | Template | What it shows |
| --- | --- | --- |
| Barcode | `ReadBarcodes_Default` | 1D/2D results with each barcode's quadrilateral drawn over the frame |
| MRZ | `ReadPassportAndId` | The composed MRZ text plus parsed fields (document type, number, birth date, expiry) |
| Document | `DetectDocumentBoundaries_Default` | The detected boundary, then a crop/rotate/filter editor with save and share |

Each mode scans a built-in sample image as soon as the SDK activates, so the app produces a result before any camera or file is involved. **Start camera** switches to live frames through [`flutter_lite_camera`](https://pub.dev/packages/flutter_lite_camera); **Scan an image file** opens a picker.

## Run it

```bash
flutter run                 # attached device or desktop
flutter run -d chrome       # web
flutter run -d windows      # or macos / linux
```

## License key

`lib/demo_bridge.dart` resolves the key at runtime:

- **Web**: `web/index.html` injects `window.FLUTTER_CAPTURE_VISION_LICENSE`, picking the Codepool demo key on `dynamsoft.com` and the public trial key on any other host. Replace that block with your own key.
- **Native**: falls back to the trial key compiled into `lib/demo_bridge_stub.dart`.

Get a 30-day trial key at <https://www.dynamsoft.com/customer/license/trialLicense/?product=dcv&package=cross-platform>.

## Analytics

On the hosted demo the page loads `demos/shared/analytics.js` and the app reports through `window.DemoAnalytics` (looked up on the parent frame). Outside that page every hook is a no-op, so `flutter run -d chrome` needs no extra setup.

## Web build for the hosted demo

```bash
flutter build web --release \
  --base-href=/codepool/demos/flutter-capture-vision-scanner/app/
```

Then copy `build/web/` into `demos/flutter-capture-vision-scanner/app/` in the Codepool site. The hosted page is <https://www.dynamsoft.com/codepool/demos/flutter-capture-vision-scanner/>.

## Tests

```bash
flutter test
```

`test/widget_test.dart` checks that the three mode choices render; `test/document_export_test.dart` covers the crop/rotate/filter math without touching the SDK.
