/// App-facing API for Dynamsoft Capture Vision.
library;

import 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart';

export 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart'
    show
        BarcodeResult,
        CaptureVisionException,
        CaptureVisionRequest,
        CaptureVisionResult,
        CaptureVisionTemplate,
        DefaultTasksCaptureVisionRequest,
        DocumentDetectionResult,
        MrzResult,
        NamedTemplateCaptureVisionRequest,
        VisionImageBuffer,
        VisionPixelFormat,
        VisionPoint,
        VisionQuadrilateral,
        VisionRotation,
        VisionTask;

/// A serial, lifecycle-aware Capture Vision router for one Flutter client.
class FlutterCaptureVision {
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;
  Set<String> _customTemplateNames = const {};

  /// Initializes the current platform SDK with a caller-supplied license key.
  Future<void> initialize({required String licenseKey}) {
    if (licenseKey.trim().isEmpty) {
      return Future<void>.error(
        const CaptureVisionException(
          code: 'invalid_license_key',
          message: 'A non-empty license key is required.',
        ),
      );
    }
    return _serialize(() async {
      _ensureNotDisposed();
      await CaptureVisionPlatform.instance.initialize(licenseKey);
      _initialized = true;
    });
  }

  /// Replaces DCV settings and returns every exact template name it declares.
  Future<List<CaptureVisionTemplate>> initSettings(String settingsJson) {
    final templates = CaptureVisionTemplate.parseAll(settingsJson);
    return _serialize(() async {
      _ensureReady();
      await CaptureVisionPlatform.instance.initSettings(settingsJson);
      _customTemplateNames = Set.unmodifiable(
        templates.map((template) => template.name),
      );
      return templates;
    });
  }

  /// Restores DCV factory-default settings and clears custom template state.
  Future<void> resetSettings() {
    return _serialize(() async {
      _ensureReady();
      await CaptureVisionPlatform.instance.resetSettings();
      _customTemplateNames = const {};
    });
  }

  /// Captures barcode, MRZ, or document results from an image file.
  Future<CaptureVisionResult> captureFile(
    String path,
    CaptureVisionRequest request,
  ) {
    if (path.trim().isEmpty) {
      return Future<CaptureVisionResult>.error(
        const CaptureVisionException(
          code: 'invalid_file_path',
          message: 'An image file path is required.',
        ),
      );
    }
    return _serialize(() async {
      _ensureReady();
      _ensureRequestIsAvailable(request);
      return CaptureVisionPlatform.instance.captureFile(path, request);
    });
  }

  /// Captures barcode, MRZ, or document results from raw image pixels.
  Future<CaptureVisionResult> captureBuffer(
    VisionImageBuffer buffer,
    CaptureVisionRequest request,
  ) {
    return _serialize(() async {
      _ensureReady();
      _ensureRequestIsAvailable(request);
      return CaptureVisionPlatform.instance.captureBuffer(buffer, request);
    });
  }

  /// Releases native resources. Calling it more than once is safe.
  Future<void> dispose() {
    if (_disposed) {
      return Future<void>.value();
    }
    _disposed = true;
    return _serialize(() async {
      if (_initialized) {
        await CaptureVisionPlatform.instance.dispose();
      }
      _initialized = false;
      _customTemplateNames = const {};
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const CaptureVisionException(
        code: 'disposed',
        message: 'This FlutterCaptureVision instance has been disposed.',
      );
    }
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw const CaptureVisionException(
        code: 'not_initialized',
        message: 'Call initialize() before using Capture Vision.',
      );
    }
  }

  void _ensureRequestIsAvailable(CaptureVisionRequest request) {
    if (_customTemplateNames.isEmpty) {
      return;
    }
    switch (request) {
      case NamedTemplateCaptureVisionRequest():
        if (!_customTemplateNames.contains(request.templateName)) {
          throw const CaptureVisionException(
            code: 'unknown_template_name',
            message: 'The named template is not in the active settings.',
          );
        }
      case DefaultTasksCaptureVisionRequest():
        final defaultNames = request.tasks
            .map((task) => task.defaultTemplateName)
            .toSet();
        if (!defaultNames.every(_customTemplateNames.contains)) {
          throw const CaptureVisionException(
            code: 'template_replaced',
            message:
                'Custom settings replaced the required default template. Call resetSettings() or use a named custom template.',
          );
        }
    }
  }
}
