import 'dart:typed_data';

import 'package:flutter_capture_vision_example/document_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports a cropped color document as PNG', () {
    final pixels = Uint8List.fromList(<int>[
      255,
      0,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
      255,
      255,
      255,
    ]);

    final output = DocumentExporter.exportRgb(
      rgb: pixels,
      width: 2,
      height: 2,
      corners: const DocumentCorners(
        topLeft: DocumentPoint(0, 0),
        topRight: DocumentPoint(1, 0),
        bottomRight: DocumentPoint(1, 1),
        bottomLeft: DocumentPoint(0, 1),
      ),
      filter: DocumentFilter.color,
    );

    expect(output.pngBytes, isNotEmpty);
    expect(output.width, 2);
    expect(output.height, 2);
  });

  test('applies grayscale and black-and-white filters deterministically', () {
    final pixels = Uint8List.fromList(<int>[255, 0, 0, 0, 0, 0]);
    const corners = DocumentCorners(
      topLeft: DocumentPoint(0, 0),
      topRight: DocumentPoint(1, 0),
      bottomRight: DocumentPoint(1, 0),
      bottomLeft: DocumentPoint(0, 0),
    );

    final grayscale = DocumentExporter.exportRgb(
      rgb: pixels,
      width: 2,
      height: 1,
      corners: corners,
      filter: DocumentFilter.grayscale,
    );
    final blackAndWhite = DocumentExporter.exportRgb(
      rgb: pixels,
      width: 2,
      height: 1,
      corners: corners,
      filter: DocumentFilter.blackAndWhite,
    );

    expect(grayscale.pngBytes, isNot(blackAndWhite.pngBytes));
  });
}
