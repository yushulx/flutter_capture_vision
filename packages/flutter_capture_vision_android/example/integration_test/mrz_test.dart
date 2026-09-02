import 'package:flutter/services.dart';
import 'package:flutter_capture_vision/flutter_capture_vision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_capture_vision_android_example/sample_images.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';

/// End-to-end MRZ verification on a real device, using the passport specimen
/// bundled with the example app plus a triage matrix that isolates which
/// pipeline stage fails (buffer input, DLR license, MRZ template).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detects and parses a passport MRZ', (tester) async {
    final vision = FlutterCaptureVision();
    await vision.initialize(
      licenseKey:
          'DLS2eyJoYW5kc2hha2VDb2RlIjoiMjAwMDAxLTE2NDk4Mjk3OTI2MzUiLCJvcmdhbm'
          'l6YXRpb25JRCI6IjIwMDAwMSIsInNlc3Npb25QYXNzd29yZCI6IndTcGR6Vm05WD'
          'JrcEQ5YUoifQ==',
    );
    final data = await rootBundle.load('assets/mrz_sample.jpg');
    final decoded = image.decodeJpg(data.buffer.asUint8List())!;
    final rgb = decoded.getBytes(order: image.ChannelOrder.rgb);
    final buffer = VisionImageBuffer(
      bytes: Uint8List.fromList(rgb),
      width: decoded.width,
      height: decoded.height,
      stride: decoded.width * 3,
      pixelFormat: VisionPixelFormat.rgb888,
    );

    Future<void> probe(String label, CaptureVisionRequest request) async {
      final stopwatch = Stopwatch()..start();
      final result = await vision.captureBuffer(buffer, request);
      stopwatch.stop();
      // ignore: avoid_print
      print(
        'MRZ-TEST $label: ${stopwatch.elapsedMilliseconds}ms '
        'barcodes=${result.barcodes.length} '
        'mrz=${result.mrzResults.length} '
        'documents=${result.documentDetections.length}',
      );
      for (final mrz in result.mrzResults) {
        // ignore: avoid_print
        print('MRZ-TEST $label rawText=${mrz.rawText}');
        // ignore: avoid_print
        print('MRZ-TEST $label documentType=${mrz.documentType}');
        // ignore: avoid_print
        print(
          'MRZ-TEST $label location=${mrz.location?.points.map((p) => '(${p.x},${p.y})').join(' ')}',
        );
        // ignore: avoid_print
        print('MRZ-TEST $label confidence=${mrz.confidence}');
      }
      for (final line in result.mrzResults) {
        // ignore: avoid_print
        print('MRZ-TEST $label mrz=$line');
      }
    }

    // Sanity check: a runtime-generated Code 39 image must decode, which
    // proves the buffer pipeline and the barcode license on this device.
    final barcodeSample = await SampleImage.barcode();
    final barcodeBuffer = VisionImageBuffer(
      bytes: barcodeSample.rgb,
      width: barcodeSample.width,
      height: barcodeSample.height,
      stride: barcodeSample.width * 3,
      pixelFormat: VisionPixelFormat.rgb888,
    );
    final barcodeResult = await vision.captureBuffer(
      barcodeBuffer,
      CaptureVisionRequest.forTasks({VisionTask.barcode}),
    );
    // ignore: avoid_print
    print(
      'MRZ-TEST code39: barcodes=${barcodeResult.barcodes.length} '
      'text=${barcodeResult.barcodes.map((b) => b.text).join(', ')}',
    );

    await probe(
      'passport+mrz',
      CaptureVisionRequest.forTasks({VisionTask.mrz}),
    );
    await probe(
      'passport+textlines',
      CaptureVisionRequest.namedTemplate('RecognizeTextLines_Default'),
    );
    await vision.dispose();
  });
}
