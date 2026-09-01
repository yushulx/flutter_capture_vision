import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'capture_vision_exception.dart';
import 'capture_vision_request.dart';
import 'capture_vision_result.dart';
import 'vision_image_buffer.dart';

/// Platform contract implemented by each flutter_capture_vision package.
abstract class CaptureVisionPlatform extends PlatformInterface {
  CaptureVisionPlatform() : super(token: _token);

  static final Object _token = Object();
  static CaptureVisionPlatform _instance = MethodChannelCaptureVision();

  /// The currently registered platform implementation.
  static CaptureVisionPlatform get instance => _instance;

  /// Registers an endorsed platform implementation.
  static set instance(CaptureVisionPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initializes the platform SDK with a caller-supplied license key.
  Future<void> initialize(String licenseKey) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Replaces the router's settings with the supplied DCV JSON settings.
  Future<void> initSettings(String settingsJson) {
    throw UnimplementedError('initSettings() has not been implemented.');
  }

  /// Restores all router templates to their DCV factory defaults.
  Future<void> resetSettings() {
    throw UnimplementedError('resetSettings() has not been implemented.');
  }

  /// Captures results from an image file.
  Future<CaptureVisionResult> captureFile(
    String path,
    CaptureVisionRequest request,
  ) {
    throw UnimplementedError('captureFile() has not been implemented.');
  }

  /// Captures results from explicitly-described raw image pixels.
  Future<CaptureVisionResult> captureBuffer(
    VisionImageBuffer buffer,
    CaptureVisionRequest request,
  ) {
    throw UnimplementedError('captureBuffer() has not been implemented.');
  }

  /// Releases native objects associated with the plugin instance.
  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}

/// MethodChannel implementation used by native Android, iOS, and desktop code.
class MethodChannelCaptureVision extends CaptureVisionPlatform {
  static const MethodChannel _channel = MethodChannel('flutter_capture_vision');

  @override
  Future<void> initialize(String licenseKey) =>
      _invokeVoid('initialize', {'licenseKey': licenseKey});

  @override
  Future<void> initSettings(String settingsJson) =>
      _invokeVoid('initSettings', {'settingsJson': settingsJson});

  @override
  Future<void> resetSettings() => _invokeVoid('resetSettings');

  @override
  Future<CaptureVisionResult> captureFile(
    String path,
    CaptureVisionRequest request,
  ) async {
    final result = await _invokeMap('captureFile', {
      'path': path,
      'request': _requestToMap(request),
    });
    return CaptureVisionResult.fromMap(result);
  }

  @override
  Future<CaptureVisionResult> captureBuffer(
    VisionImageBuffer buffer,
    CaptureVisionRequest request,
  ) async {
    final result = await _invokeMap('captureBuffer', {
      'buffer': {
        'bytes': buffer.bytes,
        'width': buffer.width,
        'height': buffer.height,
        'stride': buffer.stride,
        'pixelFormat': buffer.pixelFormat.name,
        'rotation': buffer.rotation.degrees,
      },
      'request': _requestToMap(request),
    });
    return CaptureVisionResult.fromMap(result);
  }

  @override
  Future<void> dispose() => _invokeVoid('dispose');

  Future<void> _invokeVoid(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw CaptureVisionException(
        code: error.code,
        message: error.message ?? 'The native Capture Vision operation failed.',
        cause: error,
      );
    }
  }

  Future<Map<Object?, Object?>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
      if (result == null) {
        throw const CaptureVisionException(
          code: 'invalid_native_result',
          message: 'The native Capture Vision operation returned no result.',
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw CaptureVisionException(
        code: error.code,
        message: error.message ?? 'The native Capture Vision operation failed.',
        cause: error,
      );
    }
  }
}

Map<String, Object?> _requestToMap(CaptureVisionRequest request) {
  return switch (request) {
    DefaultTasksCaptureVisionRequest() => {
      'type': 'tasks',
      'tasks': request.tasks.map((task) => task.id).toList(growable: false),
    },
    NamedTemplateCaptureVisionRequest() => {
      'type': 'template',
      'templateName': request.templateName,
    },
  };
}
