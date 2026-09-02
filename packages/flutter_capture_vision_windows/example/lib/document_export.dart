import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// The color treatment used when exporting a captured document.
enum DocumentFilter { color, grayscale, blackAndWhite }

/// A point in source-image pixels.
class DocumentPoint {
  const DocumentPoint(this.x, this.y);

  final double x;
  final double y;
}

/// Editable document corners, ordered clockwise from the upper-left corner.
class DocumentCorners {
  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final DocumentPoint topLeft;
  final DocumentPoint topRight;
  final DocumentPoint bottomRight;
  final DocumentPoint bottomLeft;

  List<DocumentPoint> get points => [
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ];

  DocumentCorners replace(int index, DocumentPoint value) => switch (index) {
    0 => DocumentCorners(
      topLeft: value,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    ),
    1 => DocumentCorners(
      topLeft: topLeft,
      topRight: value,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    ),
    2 => DocumentCorners(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: value,
      bottomLeft: bottomLeft,
    ),
    3 => DocumentCorners(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: value,
    ),
    _ => throw RangeError.index(index, points, 'index'),
  };
}

/// A portable PNG export produced from the captured RGB frame.
class DocumentExport {
  const DocumentExport({
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final int width;
  final int height;
}

/// Rectifies a selected quadrilateral with bilinear sampling, then applies the
/// selected presentation filter. This keeps the example self-contained and
/// works on every Flutter target without platform-specific image APIs.
class DocumentExporter {
  static DocumentExport exportRgb({
    required Uint8List rgb,
    required int width,
    required int height,
    required DocumentCorners corners,
    required DocumentFilter filter,
  }) {
    if (width <= 0 || height <= 0 || rgb.lengthInBytes < width * height * 3) {
      throw ArgumentError.value(rgb, 'rgb', 'Invalid RGB frame geometry.');
    }
    final source = image.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      bytesOffset: rgb.offsetInBytes,
      rowStride: width * 3,
      order: image.ChannelOrder.rgb,
    );
    final outputWidth =
        math
            .max(
              _sideLength(corners.topLeft, corners.topRight),
              _sideLength(corners.bottomLeft, corners.bottomRight),
            )
            .round()
            .clamp(0, math.max(0, width - 1))
            .toInt() +
        1;
    final outputHeight =
        math
            .max(
              _sideLength(corners.topLeft, corners.bottomLeft),
              _sideLength(corners.topRight, corners.bottomRight),
            )
            .round()
            .clamp(0, math.max(0, height - 1))
            .toInt() +
        1;
    final output = image.Image(width: outputWidth, height: outputHeight);

    for (var y = 0; y < outputHeight; y++) {
      final v = outputHeight == 1 ? 0.0 : y / (outputHeight - 1);
      for (var x = 0; x < outputWidth; x++) {
        final u = outputWidth == 1 ? 0.0 : x / (outputWidth - 1);
        final sourcePoint = _interpolate(corners, u, v);
        final pixel = source.getPixel(
          sourcePoint.x.round().clamp(0, width - 1).toInt(),
          sourcePoint.y.round().clamp(0, height - 1).toInt(),
        );
        final channels = _applyFilter(
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          filter,
        );
        output.setPixelRgb(x, y, channels.$1, channels.$2, channels.$3);
      }
    }

    return DocumentExport(
      pngBytes: Uint8List.fromList(image.encodePng(output)),
      width: outputWidth,
      height: outputHeight,
    );
  }

  static double _sideLength(DocumentPoint first, DocumentPoint second) => math
      .sqrt(math.pow(second.x - first.x, 2) + math.pow(second.y - first.y, 2));

  static DocumentPoint _interpolate(
    DocumentCorners corners,
    double u,
    double v,
  ) {
    final leftX =
        corners.topLeft.x + (corners.bottomLeft.x - corners.topLeft.x) * v;
    final leftY =
        corners.topLeft.y + (corners.bottomLeft.y - corners.topLeft.y) * v;
    final rightX =
        corners.topRight.x + (corners.bottomRight.x - corners.topRight.x) * v;
    final rightY =
        corners.topRight.y + (corners.bottomRight.y - corners.topRight.y) * v;
    return DocumentPoint(
      leftX + (rightX - leftX) * u,
      leftY + (rightY - leftY) * u,
    );
  }

  static (int, int, int) _applyFilter(
    int red,
    int green,
    int blue,
    DocumentFilter filter,
  ) {
    switch (filter) {
      case DocumentFilter.color:
        return (red, green, blue);
      case DocumentFilter.grayscale:
        final gray = (red * 0.299 + green * 0.587 + blue * 0.114).round();
        return (gray, gray, gray);
      case DocumentFilter.blackAndWhite:
        final gray = red * 0.299 + green * 0.587 + blue * 0.114;
        final value = gray >= 160 ? 255 : 0;
        return (value, value, value);
    }
  }
}
