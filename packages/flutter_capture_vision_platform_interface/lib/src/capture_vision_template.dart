import 'dart:convert';

import 'capture_vision_exception.dart';

/// A named Capture Vision template declared in a DCV settings JSON document.
class CaptureVisionTemplate {
  /// Creates a template with the exact [name] declared in DCV settings.
  const CaptureVisionTemplate(this.name);

  /// The case-sensitive name passed unchanged to CaptureVisionRouter.
  final String name;

  /// Extracts template names from a DCV settings JSON document.
  ///
  /// DCV declares templates in `CaptureVisionTemplates[].Name`. Names retain
  /// their source order and exact spelling because DCV resolves them by name.
  /// Invalid settings are rejected before anything reaches a native SDK.
  static List<CaptureVisionTemplate> parseAll(String settingsJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(settingsJson);
    } on FormatException catch (error) {
      throw CaptureVisionException(
        code: 'invalid_template_settings',
        message: 'Template settings must be valid JSON.',
        cause: error,
      );
    }

    if (decoded is! Map) {
      throw const CaptureVisionException(
        code: 'invalid_template_settings',
        message: 'Template settings must be a JSON object.',
      );
    }

    final Object? rawTemplates = decoded['CaptureVisionTemplates'];
    if (rawTemplates is! List || rawTemplates.isEmpty) {
      throw const CaptureVisionException(
        code: 'invalid_template_settings',
        message: 'Template settings must declare CaptureVisionTemplates.',
      );
    }

    final names = <String>{};
    final templates = <CaptureVisionTemplate>[];
    for (final Object? rawTemplate in rawTemplates) {
      if (rawTemplate is! Map) {
        throw const CaptureVisionException(
          code: 'invalid_template_settings',
          message: 'Every capture vision template must be a JSON object.',
        );
      }

      final Object? rawName = rawTemplate['Name'];
      if (rawName is! String || rawName.trim().isEmpty) {
        throw const CaptureVisionException(
          code: 'invalid_template_settings',
          message: 'Every capture vision template must have a non-empty Name.',
        );
      }
      if (!names.add(rawName)) {
        throw const CaptureVisionException(
          code: 'duplicate_template_name',
          message: 'Capture vision template names must be unique.',
        );
      }

      templates.add(CaptureVisionTemplate(rawName));
    }

    return List.unmodifiable(templates);
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureVisionTemplate && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'CaptureVisionTemplate($name)';
}
