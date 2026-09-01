/// A built-in Capture Vision capability with a stable wire identifier.
class VisionTask {
  const VisionTask._(this.id, this.defaultTemplateName);

  /// Decodes 1D and 2D barcodes.
  static const barcode = VisionTask._('barcode', 'ReadBarcodes_Default');

  /// Recognizes and parses passport and ID-card MRZ data.
  static const mrz = VisionTask._('mrz', 'ReadPassportAndId');

  /// Locates a document's four boundary corners.
  static const documentDetection = VisionTask._(
    'documentDetection',
    'DetectDocumentBoundaries_Default',
  );

  /// Stable identifier used in the platform-channel protocol.
  final String id;

  /// Factory-default DCV template used by a task request.
  final String defaultTemplateName;

  @override
  bool operator ==(Object other) => other is VisionTask && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VisionTask($id)';
}
