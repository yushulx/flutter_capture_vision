import 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart';

/// Android registration for the shared method-channel implementation.
class FlutterCaptureVisionPlugin {
  static void registerWith() {
    CaptureVisionPlatform.instance = MethodChannelCaptureVision();
  }
}
