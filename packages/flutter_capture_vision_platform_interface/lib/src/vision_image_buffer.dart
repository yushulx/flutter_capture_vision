import 'dart:typed_data';

import 'capture_vision_exception.dart';

/// Pixel layouts accepted by the Capture Vision raw-image API.
enum VisionPixelFormat {
  binary,
  grayscale,
  nv21,
  nv12,
  rgb565,
  rgb555,
  rgb888,
  bgr888,
  argb8888,
  abgr8888;

  int get minimumBytesPerPixel => switch (this) {
    VisionPixelFormat.rgb888 || VisionPixelFormat.bgr888 => 3,
    VisionPixelFormat.argb8888 || VisionPixelFormat.abgr8888 => 4,
    VisionPixelFormat.rgb565 || VisionPixelFormat.rgb555 => 2,
    _ => 1,
  };
}

/// Clockwise rotation applied to a raw image before results are reported.
enum VisionRotation {
  degrees0(0),
  degrees90(90),
  degrees180(180),
  degrees270(270);

  const VisionRotation(this.degrees);

  /// The clockwise angle in degrees.
  final int degrees;
}

/// Raw image data with explicit geometry and pixel layout.
class VisionImageBuffer {
  /// Creates a validated raw image input.
  VisionImageBuffer({
    required this.bytes,
    required this.width,
    required this.height,
    required this.stride,
    required this.pixelFormat,
    this.rotation = VisionRotation.degrees0,
  }) {
    if (width <= 0 || height <= 0) {
      throw const CaptureVisionException(
        code: 'invalid_image_dimensions',
        message: 'Image width and height must be greater than zero.',
      );
    }
    if (stride < width * pixelFormat.minimumBytesPerPixel) {
      throw const CaptureVisionException(
        code: 'invalid_image_stride',
        message: 'Image stride is too small for its width and pixel format.',
      );
    }
    if (bytes.lengthInBytes < stride * height) {
      throw const CaptureVisionException(
        code: 'invalid_image_buffer',
        message: 'Image bytes do not contain the declared image area.',
      );
    }
  }

  /// Pixels in the declared [pixelFormat].
  final Uint8List bytes;

  /// Pixel width of the source frame.
  final int width;

  /// Pixel height of the source frame.
  final int height;

  /// Bytes between adjacent pixel rows.
  final int stride;

  /// Memory layout of [bytes].
  final VisionPixelFormat pixelFormat;

  /// Clockwise orientation correction for [bytes].
  final VisionRotation rotation;
}
