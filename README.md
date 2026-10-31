# flutter_capture_vision

[![pub package](https://img.shields.io/pub/v/flutter_capture_vision.svg)](https://pub.dev/packages/flutter_capture_vision)

Monorepo for the `flutter_capture_vision` federated Flutter plugin — a wrapper of [Dynamsoft Capture Vision](https://www.dynamsoft.com/capture-vision/overview/) for **Android**, **iOS**, **Web**, **Windows**, **Linux**, and **macOS**. It provides barcode reading, MRZ (passport/ID) recognition, and document boundary detection behind one stable Dart API.

Live web demo: <https://www.dynamsoft.com/codepool/demos/flutter-capture-vision-scanner/>

See the main package [README](packages/flutter_capture_vision/README.md) for getting started, usage, and platform notes.

## Repository Structure

All packages are siblings under [`packages/`](packages/) and are published to [pub.dev](https://pub.dev) independently:

| Package | Description |
|---------|-------------|
| [`flutter_capture_vision`](packages/flutter_capture_vision) | App-facing package. Add this to your app. |
| [`flutter_capture_vision_platform_interface`](packages/flutter_capture_vision_platform_interface) | Platform interface contract and shared data models. |
| [`flutter_capture_vision_android`](packages/flutter_capture_vision_android) | Android implementation. |
| [`flutter_capture_vision_ios`](packages/flutter_capture_vision_ios) | iOS implementation. |
| [`flutter_capture_vision_web`](packages/flutter_capture_vision_web) | Web implementation with a self-hosted WASM bundle. |
| [`flutter_capture_vision_windows`](packages/flutter_capture_vision_windows) | Windows implementation. |
| [`flutter_capture_vision_macos`](packages/flutter_capture_vision_macos) | macOS implementation. |
| [`flutter_capture_vision_linux`](packages/flutter_capture_vision_linux) | Linux implementation. |

The platform packages are **endorsed** by the app-facing package, so app developers only need to depend on `flutter_capture_vision`.

## Bundled SDK Versions

| Platform | SDK | Version |
|----------|-----|---------|
| Android | `com.dynamsoft:mrzscannerbundle` | 3.6.2000 |
| iOS | `DynamsoftMRZScannerBundle` | 3.6.2000 |
| Web | `dynamsoft-capture-vision-bundle` (WASM, self-hosted asset) | 3.6.3200 |
| Windows | Desktop bundle (x64 DLLs) | 3.6.5000 |
| macOS | Desktop bundle (universal2 dylibs) | 3.6.5000 |
| Linux | Desktop bundle (x64 and arm64 `.so`) | 3.6.5000 |

Bumping a version means replacing the vendored binaries and resource set (`Templates`, `Models`, `ParserResources`, the root `.data` files) together — the desktop packages resolve those resources relative to the libraries, so a mixed set fails at runtime rather than at build time.

## Development

The repository uses a [pub workspace](https://dart.dev/tools/pub/workspaces) — run `flutter pub get` once at the repository root and all packages resolve local dependencies automatically.

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test   # inside packages that ship tests
```

Each package has its own `example/` app for standalone testing, e.g.:

```bash
cd packages/flutter_capture_vision/example
flutter run -d macos   # or windows / linux / chrome / a device
```

## Publishing

Each package is published independently from its own directory, with its own
version and CHANGELOG:

```bash
cd packages/flutter_capture_vision_web
dart pub publish --dry-run   # validate first
dart pub publish
```

Because each platform package ships its own native binaries, each package gets
the full 100 MB pub.dev size limit independently. The `archive-size-guard` CI
job measures every package before a release and fails above 100 MB, so a
platform that grows past the limit is caught in CI instead of during upload.

Publishing from CI is manual: run the **Publish to pub.dev** workflow
(`workflow_dispatch`) and pick a package, or `all_without_facade` to publish the
seven implementation packages in dependency order. It requires the
`PUB_PUBLISH_AUTH_TOKEN` repository secret. There is no tag trigger — the pub
client cannot complete the OIDC exchange from this repository, so a tag would
only produce a run that hangs on the interactive login prompt.

## License

See [LICENSE](LICENSE).
