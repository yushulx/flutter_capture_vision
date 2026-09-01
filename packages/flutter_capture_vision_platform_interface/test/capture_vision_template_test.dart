import 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptureVisionTemplate.parseAll', () {
    test('returns every template name in declaration order', () {
      const settings = '''
{
  "CaptureVisionTemplates": [
    {"Name": "FastBarcode"},
    {"Name": "PassportMrz"},
    {"Name": "DocumentEdges"}
  ]
}
''';

      final templates = CaptureVisionTemplate.parseAll(settings);

      expect(templates.map((template) => template.name), [
        'FastBarcode',
        'PassportMrz',
        'DocumentEdges',
      ]);
    });

    test('preserves case-sensitive template names', () {
      const settings = '''
{"CaptureVisionTemplates": [{"Name": "My_Custom_Template"}]}
''';

      final template = CaptureVisionTemplate.parseAll(settings).single;

      expect(template.name, 'My_Custom_Template');
    });

    test('rejects missing, blank, and duplicate template names', () {
      expect(
        () => CaptureVisionTemplate.parseAll('{}'),
        throwsA(isA<CaptureVisionException>()),
      );
      expect(
        () => CaptureVisionTemplate.parseAll(
          '''{"CaptureVisionTemplates": [{"Name": "   "}]}''',
        ),
        throwsA(isA<CaptureVisionException>()),
      );
      expect(
        () => CaptureVisionTemplate.parseAll('''
{"CaptureVisionTemplates": [{"Name": "Duplicate"}, {"Name": "Duplicate"}]}
'''),
        throwsA(isA<CaptureVisionException>()),
      );
    });
  });
}
