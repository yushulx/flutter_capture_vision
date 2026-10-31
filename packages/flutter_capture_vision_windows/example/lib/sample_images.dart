import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as image;

/// Runtime-generated demo images, one per vision task, so the example proves
/// the SDK works out of the box — before any camera or user file is involved.
///
/// The samples are drawn with plain raster code plus `TextPainter` text, so no
/// binary assets ship with the example apps. They are sized for a portrait
/// phone screen (roughly 3:2 or narrower) and rendered large enough for the
/// Dynamsoft neural models to localize and recognize them reliably.
class SampleImage {
  const SampleImage._(this.pngBytes, this.rgb, this.width, this.height);

  /// Encoded image bytes (PNG or JPEG) for display.
  final Uint8List pngBytes;

  /// Raw RGB888 pixels for `VisionImageBuffer`.
  final Uint8List rgb;
  final int width;
  final int height;

  static Future<SampleImage> barcode() async {
    const text = 'DCV2026';
    const narrow = 3;
    const wide = 8;
    const gap = 5;
    const barHeight = 150;
    const margin = 40;

    // Code 39 element patterns: nine alternating bars and spaces per
    // character, `w` = wide, `n` = narrow. `*` frames the payload.
    const patterns = <String, String>{
      '0': 'nnnwwnwnn',
      '1': 'wnnwnnnnw',
      '2': 'nnwwnnnnw',
      '3': 'wnwwnnnnn',
      '4': 'nnnwwnnnw',
      '5': 'wnnwwnnnn',
      '6': 'nnwwwnnnn',
      '7': 'nnnwnnwnw',
      '8': 'wnnwnnwnn',
      '9': 'nnwwnnwnn',
      'A': 'wnnnnwnnw',
      'B': 'nnwnnwnnw',
      'C': 'wnwnnwnnn',
      'D': 'nnnnwwnnw',
      'E': 'wnnnwwnnn',
      'F': 'nnwnwwnnn',
      'G': 'nnnnnwwnw',
      'H': 'wnnnnwwnn',
      'I': 'nnwnnwwnn',
      'J': 'nnnnwwwnn',
      'K': 'wnnnnnnww',
      'L': 'nnwnnnnww',
      'M': 'wnwnnnnwn',
      'N': 'nnnnwnnww',
      'O': 'wnnnwnnwn',
      'P': 'nnwnwnnwn',
      'Q': 'nnnnnnwww',
      'R': 'wnnnnnwwn',
      'S': 'nnwnnnwwn',
      'T': 'nnnnwnwwn',
      'U': 'wwnnnnnnw',
      'V': 'nwwnnnnnw',
      'W': 'wwwnnnnnn',
      'X': 'nwnnwnnnw',
      'Y': 'wwnnwnnnn',
      'Z': 'nwwnwnnnn',
      '-': 'nwnnnnwnw',
      '.': 'wwnnnnwnn',
      ' ': 'nwwnnnwnn',
      '*': 'nwnnwnwnn',
    };

    var modules = 0;
    for (final character in '*$text*'.split('')) {
      final pattern = patterns[character]!;
      for (final element in pattern.split('')) {
        modules += element == 'w' ? wide : narrow;
      }
      modules += gap;
    }
    final width = margin * 2 + modules;
    final height = barHeight + margin * 2;
    final canvas = image.Image(width: width, height: height);
    image.fill(canvas, color: image.ColorRgb8(255, 255, 255));

    var x = margin;
    for (final character in '*$text*'.split('')) {
      final pattern = patterns[character]!;
      for (var index = 0; index < pattern.length; index++) {
        final elementWidth = pattern[index] == 'w' ? wide : narrow;
        if (index.isEven) {
          image.fillRect(
            canvas,
            x1: x,
            y1: margin,
            x2: x + elementWidth - 1,
            y2: margin + barHeight - 1,
            color: image.ColorRgb8(0, 0, 0),
          );
        }
        x += elementWidth;
      }
      x += gap;
    }
    return _encode(canvas);
  }

  /// A real specimen passport page (ICAO TD3) shipped as an example asset.
  /// The MRZ neural models are trained on document photography, so a genuine
  /// sample is required for reliable localization and recognition.
  static Future<SampleImage> mrz() async {
    final data = await rootBundle.load('assets/mrz_sample.jpg');
    final decoded = image.decodeJpg(data.buffer.asUint8List());
    if (decoded == null) {
      throw const FormatException(
        'The bundled MRZ sample is not a valid image.',
      );
    }
    return _encode(decoded, encoded: data.buffer.asUint8List());
  }

  static Future<SampleImage> document() async {
    const width = 960;
    const height = 720;
    final canvas = image.Image(width: width, height: height);
    image.fill(canvas, color: image.ColorRgb8(88, 96, 106));
    // A slightly rotated white "page" on a plain desk gives the detector four
    // clean corners. The page fills most of the frame: the preview shows the
    // whole image (letterboxed), so a small page would end up too small to read
    // the text lines once the sample is scaled down.
    final page = [
      image.Point(60, 45),
      image.Point(905, 75),
      image.Point(875, 680),
      image.Point(45, 645),
    ];
    image.drawPolygon(
      canvas,
      vertices: page,
      color: image.ColorRgb8(252, 252, 250),
    );
    // Text-ish lines, interpolated along both page edges so every row stays
    // inside the sheet instead of running off the bottom.
    const rows = 9;
    for (var row = 0; row < rows; row++) {
      final t = (row + 0.7) / (rows + 0.4);
      final leftX = page[0].x + (page[3].x - page[0].x) * t + 70;
      final leftY = page[0].y + (page[3].y - page[0].y) * t;
      final rightX = page[1].x + (page[2].x - page[1].x) * t - 70;
      final rightY = page[1].y + (page[2].y - page[1].y) * t;
      image.drawLine(
        canvas,
        x1: leftX.toInt(),
        y1: leftY.toInt(),
        x2: rightX.toInt(),
        y2: rightY.toInt(),
        color: image.ColorRgb8(72, 76, 84),
        thickness: 6,
      );
    }
    return _encode(canvas);
  }

  static Future<SampleImage> _encode(
    image.Image canvas, {
    Uint8List? encoded,
  }) async {
    final png = encoded ?? Uint8List.fromList(image.encodePng(canvas));
    final channels = canvas.numChannels;
    final bytes = canvas.toUint8List();
    if (channels == 3) {
      return SampleImage._(png, bytes, canvas.width, canvas.height);
    }
    final rgb = Uint8List(canvas.width * canvas.height * 3);
    for (var index = 0; index < canvas.width * canvas.height; index++) {
      rgb[index * 3] = bytes[index * channels];
      rgb[index * 3 + 1] = bytes[index * channels + 1];
      rgb[index * 3 + 2] = bytes[index * channels + 2];
    }
    return SampleImage._(png, rgb, canvas.width, canvas.height);
  }
}
