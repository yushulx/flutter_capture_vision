import 'package:flutter_capture_vision/flutter_capture_vision.dart';
import 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeCaptureVisionPlatform platform;

  setUp(() {
    platform = _FakeCaptureVisionPlatform();
    CaptureVisionPlatform.instance = platform;
  });

  test('uses the exact dynamically discovered custom template name', () async {
    const settings = '''
{
  "CaptureVisionTemplates": [{"Name": "Passport_Reader_V2"}]
}
''';
    final vision = FlutterCaptureVision();

    await vision.initialize(licenseKey: 'test-license');
    final templates = await vision.initSettings(settings);
    await vision.captureFile(
      '/tmp/passport.jpg',
      CaptureVisionRequest.namedTemplate(templates.single.name),
    );

    expect(platform.initializedSettings, settings);
    expect(platform.lastRequest, isA<NamedTemplateCaptureVisionRequest>());
    expect(
      (platform.lastRequest! as NamedTemplateCaptureVisionRequest).templateName,
      'Passport_Reader_V2',
    );
  });

  test(
    'requires reset before default tasks can use replaced templates',
    () async {
      const settings = '''
{"CaptureVisionTemplates": [{"Name": "CustomBarcode"}]}
''';
      final vision = FlutterCaptureVision();

      await vision.initialize(licenseKey: 'test-license');
      await vision.initSettings(settings);

      await expectLater(
        () => vision.captureFile(
          '/tmp/barcode.jpg',
          CaptureVisionRequest.forTasks({VisionTask.barcode}),
        ),
        throwsA(
          isA<CaptureVisionException>().having(
            (error) => error.code,
            'code',
            'template_replaced',
          ),
        ),
      );

      await vision.resetSettings();
      await vision.captureFile(
        '/tmp/barcode.jpg',
        CaptureVisionRequest.forTasks({VisionTask.barcode}),
      );

      expect(platform.resetSettingsCalls, 1);
      expect(platform.lastRequest, isA<DefaultTasksCaptureVisionRequest>());
    },
  );
}

class _FakeCaptureVisionPlatform extends CaptureVisionPlatform {
  String? initializedSettings;
  CaptureVisionRequest? lastRequest;
  int resetSettingsCalls = 0;

  @override
  Future<CaptureVisionResult> captureBuffer(
    VisionImageBuffer buffer,
    CaptureVisionRequest request,
  ) async {
    lastRequest = request;
    return const CaptureVisionResult();
  }

  @override
  Future<CaptureVisionResult> captureFile(
    String path,
    CaptureVisionRequest request,
  ) async {
    lastRequest = request;
    return const CaptureVisionResult();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize(String licenseKey) async {}

  @override
  Future<void> initSettings(String settingsJson) async {
    initializedSettings = settingsJson;
  }

  @override
  Future<void> resetSettings() async {
    resetSettingsCalls += 1;
  }
}
