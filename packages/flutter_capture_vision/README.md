# flutter_capture_vision

[![pub package](https://img.shields.io/pub/v/flutter_capture_vision.svg)](https://pub.dev/packages/flutter_capture_vision)
[![GitHub license](https://img.shields.io/github/license/yushulx/flutter_capture_vision)](https://github.com/yushulx/flutter_capture_vision/blob/main/LICENSE)

A cross-platform Flutter plugin for barcode reading, MRZ (passport/ID) recognition, and document boundary detection, powered by [Dynamsoft Capture Vision](https://www.dynamsoft.com/capture-vision/overview/). Supports **Android**, **iOS**, **Web**, **Windows**, **Linux**, and **macOS**.

**[Try the live web demo →](https://www.dynamsoft.com/codepool/demos/flutter-capture-vision-scanner/)** — the example app running in your browser, no install or sign-up.

![Dynamsoft Capture Vision Flutter example: MRZ recognition on a passport](example/screenshot.png)

The plugin wraps the Dynamsoft Capture Vision SDK of each platform behind one stable Dart API. It accepts image **files** or **raw pixel buffers**, so it composes with any camera plugin — for example [`flutter_lite_camera`](https://pub.dev/packages/flutter_lite_camera) for live preview and frame capture.

## Getting Started

### 1. Install the Package

```yaml
dependencies:
  flutter_capture_vision: ^0.2.0
```

The Android, iOS, Web, Windows, macOS, and Linux implementations are endorsed federated packages and are selected automatically — depend only on `flutter_capture_vision`.

### 2. Obtain a License Key

A valid license is required to activate barcode, MRZ, and document detection.

[![Get Trial License](https://img.shields.io/badge/Get-30--day%20FREE%20Trial-blue)](https://www.dynamsoft.com/customer/license/trialLicense/?product=dcv&package=cross-platform)

### 3. Initialize the SDK

```dart
import 'package:flutter_capture_vision/flutter_capture_vision.dart';

final vision = FlutterCaptureVision();
await vision.initialize(licenseKey: 'YOUR-LICENSE-KEY');
```

## Usage

### Capture from an Image File

```dart
final result = await vision.captureFile(
  '/path/to/image.jpg',
  const CaptureVisionRequest.forTasks({VisionTask.barcode}),
);

for (final barcode in result.barcodes) {
  print('${barcode.format}: ${barcode.text}');
}
```

### Capture from a Camera Buffer

```dart
final result = await vision.captureBuffer(
  VisionImageBuffer(
    bytes: rgbBytes,       // Uint8List
    width: width,
    height: height,
    stride: width * 3,
    pixelFormat: VisionPixelFormat.rgb888,
    rotation: VisionRotation.degrees0,
  ),
  const CaptureVisionRequest.forTasks({
    VisionTask.barcode,
    VisionTask.mrz,
    VisionTask.documentDetection,
  }),
);
```

`CaptureVisionResult` always returns non-null lists; "nothing found" is an empty list. Failures (license, invalid input, native SDK errors) throw `CaptureVisionException(code, message)` with a stable machine-readable `code`.

## Vision Tasks

| Task | Built-in template | Results |
| --- | --- | --- |
| `VisionTask.barcode` | `ReadBarcodes_Default` | `result.barcodes` |
| `VisionTask.mrz` | `ReadPassportAndId` | `result.mrzResults` |
| `VisionTask.documentDetection` | `DetectDocumentBoundaries_Default` | `result.documentDetections` |

MRZ results carry the composed `rawText`, the parsed `fields` (passport number, date of birth, …), and the `documentType` (`MRTD_TD3_PASSPORT`, `MRTD_TD1_ID`, …). Passports and ID cards need reasonably sharp, high-resolution input — request at least 1080p from the camera for MRZ scanning.

## Custom Settings

Advanced users can replace the built-in templates with a Dynamsoft Capture Vision template JSON:

```dart
final templates = await vision.initSettings(settingsJson);   // returns parsed template names
final result = await vision.captureFile(
  path,
  CaptureVisionRequest.namedTemplate(templates.first.name),
);
await vision.resetSettings();                                // restore factory defaults
```

## Bundled SDK Versions

Each platform package compiles against — or vendors — the current Dynamsoft Capture Vision release for that platform:

| Platform | SDK | Version |
| --- | --- | --- |
| Android | `com.dynamsoft:mrzscannerbundle` | 3.6.2000 |
| iOS | `DynamsoftMRZScannerBundle` | 3.6.2000 |
| Web | `dynamsoft-capture-vision-bundle` (WASM, self-hosted) | 3.6.3200 |
| Windows | Dynamsoft Capture Vision desktop bundle | 3.6.5000 |
| macOS | Dynamsoft Capture Vision desktop bundle (universal2) | 3.6.5000 |
| Linux | Dynamsoft Capture Vision desktop bundle (x64 and arm64) | 3.6.5000 |

The MRZ Scanner bundle used on Android and iOS is a superset of the Capture Vision bundle: it also ships the MRZ neural models and the `mrzscanner-mobile-templates.json` template document, without which the built-in MRZ templates return no results. The desktop and web packages vendor the same templates, models, and parser resources inside the package, so no separate download or CDN script is required.

## Platform Notes

- **Android**: `minSdkVersion 21`.
- **iOS**: requires iOS 13+; add `NSCameraUsageDescription` when using a camera plugin.
- **Web**: serve over HTTPS or `localhost`. The JS/WASM/models bundle is self-hosted as package assets — no CDN `<script>` tag is needed.
- **Windows/Linux/macOS**: the released app bundle carries the DCV libraries and resources; see each platform package README for details.

## Examples

Each package ships a runnable example app:

```bash
cd example
flutter run                 # Android/iOS desktop or device
flutter run -d chrome       # Web
flutter run -d windows      # Windows/Linux/macOS
```

The [facade example](https://github.com/yushulx/flutter_capture_vision/tree/main/packages/flutter_capture_vision/example) is the full six-platform demo with live camera capture, annotation overlay, and document export. Its web build is hosted at **[dynamsoft.com/codepool/demos/flutter-capture-vision-scanner](https://www.dynamsoft.com/codepool/demos/flutter-capture-vision-scanner/)** if you want to try the three vision tasks before installing anything.

## License

See [LICENSE](LICENSE).
