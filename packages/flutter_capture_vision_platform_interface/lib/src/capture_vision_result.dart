import 'dart:typed_data';

/// Results produced by one Capture Vision operation.
class CaptureVisionResult {
  /// Creates a result with empty collections for capabilities that found none.
  const CaptureVisionResult({
    this.barcodes = const [],
    this.mrzResults = const [],
    this.documentDetections = const [],
  });

  /// Decoded barcode results.
  final List<BarcodeResult> barcodes;

  /// Parsed machine-readable-zone results.
  final List<MrzResult> mrzResults;

  /// Detected document boundary results.
  final List<DocumentDetectionResult> documentDetections;

  /// Decodes the versioned platform-channel result envelope.
  factory CaptureVisionResult.fromMap(Map<Object?, Object?> map) {
    List<Object?> valuesFor(String key) {
      final value = map[key];
      return value is List ? List<Object?>.from(value) : const [];
    }

    return CaptureVisionResult(
      barcodes: List.unmodifiable(
        valuesFor(
          'barcodes',
        ).whereType<Map>().map((value) => BarcodeResult.fromMap(value)),
      ),
      mrzResults: List.unmodifiable(
        valuesFor(
          'mrzResults',
        ).whereType<Map>().map((value) => MrzResult.fromMap(value)),
      ),
      documentDetections: List.unmodifiable(
        valuesFor('documentDetections').whereType<Map>().map(
          (value) => DocumentDetectionResult.fromMap(value),
        ),
      ),
    );
  }
}

/// A point in source-image coordinates.
class VisionPoint {
  const VisionPoint(this.x, this.y);

  factory VisionPoint.fromMap(Map<Object?, Object?> map) {
    final x = map['x'];
    final y = map['y'];
    if (x is! num || y is! num) {
      throw const FormatException('A vision point requires numeric x and y.');
    }
    return VisionPoint(x.toDouble(), y.toDouble());
  }

  final double x;

  /// Vertical coordinate in source-image pixels.
  final double y;
}

/// Four source-image coordinates describing a detected region.
class VisionQuadrilateral {
  VisionQuadrilateral(Iterable<VisionPoint> points)
    : points = List.unmodifiable(points) {
    if (this.points.length != 4) {
      throw const FormatException(
        'A vision quadrilateral requires four points.',
      );
    }
  }

  factory VisionQuadrilateral.fromMap(Map<Object?, Object?> map) {
    final rawPoints = map['points'];
    if (rawPoints is! List) {
      throw const FormatException('A vision quadrilateral requires points.');
    }
    return VisionQuadrilateral(
      rawPoints.whereType<Map>().map(VisionPoint.fromMap),
    );
  }

  /// Corner points ordered clockwise from the top-left corner.
  final List<VisionPoint> points;
}

/// A decoded barcode and its location.
class BarcodeResult {
  const BarcodeResult({
    required this.format,
    required this.text,
    required this.location,
    this.rawBytes,
    this.confidence,
  });

  factory BarcodeResult.fromMap(Map<Object?, Object?> map) {
    final rawBytes = map['rawBytes'];
    return BarcodeResult(
      format: map['format'] as String? ?? '',
      text: map['text'] as String? ?? '',
      location: VisionQuadrilateral.fromMap(_map(map['location'])),
      rawBytes: rawBytes is Uint8List
          ? rawBytes
          : rawBytes is List
          ? Uint8List.fromList(
              rawBytes.whereType<num>().map((v) => v.toInt()).toList(),
            )
          : null,
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }

  /// Symbology name reported by the SDK, for example `QR_CODE`.
  final String format;

  /// Decoded barcode payload as text.
  final String text;

  /// Barcode corners in source-image coordinates.
  final VisionQuadrilateral location;

  /// Decoded payload bytes when the SDK exposes them.
  final Uint8List? rawBytes;

  /// Recognition confidence in the range 0..1 when the SDK reports one.
  final double? confidence;
}

/// Parsed MRZ data and its detected location.
class MrzResult {
  const MrzResult({
    required this.rawText,
    this.location,
    this.documentType,
    this.fields = const {},
    this.confidence,
  });

  factory MrzResult.fromMap(Map<Object?, Object?> map) {
    final rawFields = map['fields'];
    final fields = rawFields is Map
        ? Map<String, String>.unmodifiable(
            rawFields.map((key, value) => MapEntry('$key', '$value')),
          )
        : const <String, String>{};
    return MrzResult(
      rawText: map['rawText'] as String? ?? '',
      documentType: map['documentType'] as String?,
      fields: fields,
      location: map['location'] is Map
          ? VisionQuadrilateral.fromMap(_map(map['location']))
          : null,
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }

  /// The composed MRZ text lines as printed on the document.
  final String rawText;

  /// MRZ document type, for example `TD1`, `TD2`, or `TD3`.
  final String? documentType;

  /// Parsed field values keyed by field name, for example `passportNumber`.
  final Map<String, String> fields;

  /// Source location when the SDK exposes one for the parsed item.
  ///
  /// DCV's code-parser result can contain structured MRZ fields without a
  /// single quadrilateral for the composed parsed item.
  final VisionQuadrilateral? location;

  /// Recognition confidence in the range 0..1 when the SDK reports one.
  final double? confidence;
}

/// A document boundary detected in the source image.
class DocumentDetectionResult {
  const DocumentDetectionResult({required this.location, this.confidence});

  factory DocumentDetectionResult.fromMap(Map<Object?, Object?> map) {
    return DocumentDetectionResult(
      location: VisionQuadrilateral.fromMap(_map(map['location'])),
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }

  /// Document corners in source-image coordinates.
  final VisionQuadrilateral location;

  /// Detection confidence in the range 0..1 when the SDK reports one.
  final double? confidence;
}

Map<Object?, Object?> _map(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.from(value);
  }
  throw const FormatException('A result item requires a map value.');
}
