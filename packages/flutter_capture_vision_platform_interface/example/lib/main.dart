import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart';

void main() => runApp(const PlatformInterfaceExampleApp());

/// Demonstrates the pure Dart contracts every platform implementation shares:
/// template-name discovery, request building, buffer validation, and typed
/// result decoding. No native SDK is required to run this example.
class PlatformInterfaceExampleApp extends StatelessWidget {
  const PlatformInterfaceExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platform Interface Example',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const ContractDemoPage(),
    );
  }
}

class ContractDemoPage extends StatefulWidget {
  const ContractDemoPage({super.key});

  @override
  State<ContractDemoPage> createState() => _ContractDemoPageState();
}

class _ContractDemoPageState extends State<ContractDemoPage> {
  static const _settingsJson =
      '{"CaptureVisionTemplates":['
      '{"Name":"ReadBarcodes_Custom"},'
      '{"Name":"ReadPassportAndId_Custom"},'
      '{"Name":"DetectDocument_Custom"}'
      ']}';

  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _demonstrateContracts();
  }

  void _demonstrateContracts() {
    // 1. Dynamically discover template names before importing settings.
    final templates = CaptureVisionTemplate.parseAll(_settingsJson);
    _log.add(
      'parseAll -> ${templates.map((template) => template.name).join(', ')}',
    );

    // 2. Build the two mutually exclusive request shapes.
    final tasksRequest = CaptureVisionRequest.forTasks({
      VisionTask.barcode,
      VisionTask.mrz,
      VisionTask.documentDetection,
    });
    if (tasksRequest is DefaultTasksCaptureVisionRequest) {
      _log.add('forTasks -> ${tasksRequest.tasks.map((t) => t.id).join(', ')}');
    }
    final namedRequest = CaptureVisionRequest.namedTemplate(
      templates.first.name,
    );
    if (namedRequest is NamedTemplateCaptureVisionRequest) {
      _log.add('namedTemplate -> ${namedRequest.templateName}');
    }

    // 3. Validate a raw pixel buffer before it reaches native code.
    final buffer = VisionImageBuffer(
      bytes: Uint8List(320 * 240 * 3),
      width: 320,
      height: 240,
      stride: 320 * 3,
      pixelFormat: VisionPixelFormat.rgb888,
      rotation: VisionRotation.degrees0,
    );
    _log.add(
      'buffer -> ${buffer.width}x${buffer.height} ${buffer.pixelFormat.name}',
    );
    try {
      VisionImageBuffer(
        bytes: Uint8List(0),
        width: 0,
        height: 0,
        stride: 0,
        pixelFormat: VisionPixelFormat.rgb888,
        rotation: VisionRotation.degrees0,
      );
    } on CaptureVisionException catch (error) {
      _log.add('invalid buffer rejected -> ${error.code}');
    }

    // 4. Decode a typed result map; unknown MRZ fields are preserved.
    final result = CaptureVisionResult.fromMap(const {
      'barcodes': [
        {
          'format': 'QR_CODE',
          'text': 'https://example.com',
          'confidence': 98,
          'location': {
            'points': [
              {'x': 1, 'y': 2},
              {'x': 3, 'y': 4},
              {'x': 5, 'y': 6},
              {'x': 7, 'y': 8},
            ],
          },
        },
      ],
      'mrzResults': [
        {
          'rawText': 'P<UTOEXAMPLE<<NAME<<<<<<<<<<<<<<<<<<<<<',
          'documentType': 'Passport',
          'fields': {'line1': 'P<UTOEXAMPLE<<NAME<<<', 'customField': 'kept'},
        },
      ],
      'documentDetections': [],
    });
    _log.add(
      'result -> ${result.barcodes.length} barcode(s), '
      '${result.mrzResults.length} MRZ, '
      '${result.documentDetections.length} detection(s)',
    );
    _log.add(
      'unknown MRZ field preserved -> ${result.mrzResults.first.fields['customField']}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contract Demo')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _log.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(_log[index]),
        ),
      ),
    );
  }
}
