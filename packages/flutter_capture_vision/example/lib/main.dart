import 'dart:async';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_capture_vision/flutter_capture_vision.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'document_export.dart';
import 'sample_images.dart';

void main() => runApp(const CaptureVisionExampleApp());

class CaptureVisionExampleApp extends StatelessWidget {
  const CaptureVisionExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Capture Vision Example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const CaptureVisionHomePage(),
  );
}

enum _VisionMode { barcode, mrz, document }

extension on _VisionMode {
  String get title => switch (this) {
    _VisionMode.barcode => 'Barcode',
    _VisionMode.mrz => 'MRZ',
    _VisionMode.document => 'Document',
  };

  VisionTask get task => switch (this) {
    _VisionMode.barcode => VisionTask.barcode,
    _VisionMode.mrz => VisionTask.mrz,
    _VisionMode.document => VisionTask.documentDetection,
  };
}

class CaptureVisionHomePage extends StatefulWidget {
  const CaptureVisionHomePage({super.key});

  @override
  State<CaptureVisionHomePage> createState() => _CaptureVisionHomePageState();
}

class _CaptureVisionHomePageState extends State<CaptureVisionHomePage> {
  // To read barcodes, MRZ, and documents, get a 30-day FREE trial license for
  // Dynamsoft Capture Vision:
  // https://www.dynamsoft.com/customer/license/trialLicense/?product=dcv&package=cross-platform
  static const String _licenseKey =
      'DLS2eyJoYW5kc2hha2VDb2RlIjoiMjAwMDAxLTE2NDk4Mjk3OTI2MzUiLCJvcmdhbml6YXRpb25JRCI6IjIwMDAwMSIsInNlc3Npb25QYXNzd29yZCI6IndTcGR6Vm05WDJrcEQ5YUoifQ==';

  final FlutterLiteCamera _camera = FlutterLiteCamera();
  final FlutterCaptureVision _vision = FlutterCaptureVision();

  _VisionMode _mode = _VisionMode.barcode;
  bool _sdkReady = false;
  String? _sdkError;
  bool _cameraOpened = false;
  bool _shouldCapture = false;
  bool _isCapturing = false;
  bool _isPickingImage = false;
  int _textureId = -1;
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _rotation = 0;
  ResolutionPreset _preset = ResolutionPreset.high;
  _RgbFrame? _lastFrame;
  CaptureVisionResult? _result;
  String? _sceneStatus;

  // Channel arrangement for the Android YUV conversion. BGR (5) is the
  // plugin default, verified against on-device colors; other devices can
  // pass a different order through captureFrame(byteOrder:).
  final int _byteOrder = 5;

  @override
  void initState() {
    super.initState();
    _initializeVision();
  }

  @override
  void dispose() {
    _shouldCapture = false;
    unawaited(_camera.stopPreview().catchError((_) {}));
    unawaited(_camera.release().catchError((_) {}));
    unawaited(_vision.dispose());
    super.dispose();
  }

  Future<void> _initializeVision() async {
    try {
      await _vision.initialize(licenseKey: _licenseKey);
      if (mounted) setState(() => _sdkReady = true);
      // Prove the SDK works immediately: run the built-in sample scene for
      // the selected mode before any camera or file is involved.
      await _runSampleScene();
    } catch (error) {
      if (mounted) setState(() => _sdkError = '$error');
    }
  }

  /// Runs the built-in sample image for the selected mode and overlays the
  /// result. Starting the camera or picking a file replaces the sample.
  Future<void> _runSampleScene() async {
    if (!_sdkReady) {
      _setSceneStatus('Waiting for the SDK to initialize…');
      return;
    }
    if (_cameraOpened || _isPickingImage || _isCapturing) {
      _setSceneStatus('The camera is busy — stop it to switch scenes.');
      return;
    }
    try {
      _setSceneStatus('Preparing the sample…');
      final sample = switch (_mode) {
        _VisionMode.barcode => SampleImage.barcode(),
        _VisionMode.mrz => SampleImage.mrz(),
        _VisionMode.document => SampleImage.document(),
      };
      final frame = _RgbFrame.fromSample(await sample);
      if (!mounted) return;
      setState(() {
        _lastFrame = frame;
        _textureId = -1;
        _frameWidth = frame.width;
        _frameHeight = frame.height;
        _result = null;
      });
      _setSceneStatus('Scanning the sample…');
      final response = await _vision.captureBuffer(
        VisionImageBuffer(
          bytes: frame.rgb,
          width: frame.width,
          height: frame.height,
          stride: frame.width * 3,
          pixelFormat: VisionPixelFormat.rgb888,
        ),
        CaptureVisionRequest.forTasks({_mode.task}),
      );
      _setSceneStatus('Sample scanned:');
      if (mounted) setState(() => _result = response);
    } catch (error) {
      _setSceneStatus('The sample scene failed: $error');
      _showMessage('The sample scene failed: $error');
    }
  }

  void _setSceneStatus(String message) {
    // Temporary diagnostics surfaced in the result panel.
    if (mounted) setState(() => _sceneStatus = message);
  }

  Future<void> _startCamera() async {
    if (!_sdkReady) {
      _showMessage(_sdkError ?? 'Capture Vision is still initializing.');
      return;
    }
    try {
      final devices = await _camera.getDeviceList();
      if (devices.isEmpty) {
        _showMessage('No camera device is available.');
        return;
      }
      if (!await _camera.open(0)) {
        _showMessage('The camera could not be opened.');
        return;
      }
      if (!await _camera.setResolutionPreset(_preset)) {
        debugPrint('setResolutionPreset($_preset) failed.');
      }
      final textureId = await _camera.startPreview();
      final width = await _camera.getWidth();
      final height = await _camera.getHeight();
      var rotation = 0;
      try {
        rotation = await _camera.getRotation();
      } catch (_) {
        // Desktop/web camera feeds do not necessarily expose a rotation.
      }
      if (!mounted) return;
      setState(() {
        _cameraOpened = true;
        _textureId = textureId;
        _frameWidth = width;
        _frameHeight = height;
        _rotation = rotation;
        _shouldCapture = true;
        _result = null;
      });
      unawaited(_captureLoop());
    } catch (error) {
      _showMessage('Could not start the camera: $error');
    }
  }

  /// Applies a resolution preset. While the camera is open the device
  /// renegotiates the stream; the actual frame size is read back afterwards
  /// because the device may fall back to a different size.
  Future<void> _applyResolution(ResolutionPreset preset) async {
    setState(() => _preset = preset);
    if (!_cameraOpened) return;
    final ok = await _camera.setResolutionPreset(preset);
    if (!ok) {
      debugPrint('setResolutionPreset($preset) failed.');
      return;
    }
    final width = await _camera.getWidth();
    final height = await _camera.getHeight();
    if (!mounted || width <= 0 || height <= 0) return;
    setState(() {
      _frameWidth = width;
      _frameHeight = height;
    });
  }

  Future<void> _stopCamera() async {
    _shouldCapture = false;
    if (!_cameraOpened) return;
    try {
      await _camera.stopPreview();
      await _camera.release();
    } catch (_) {
      // Releasing an already-disconnected camera is harmless for this demo.
    }
    if (mounted) {
      setState(() {
        _cameraOpened = false;
        _textureId = -1;
      });
    }
  }

  Future<void> _captureLoop() async {
    if (!_shouldCapture || !_cameraOpened) return;
    // Mirrors the flutter_barcode_sdk example: at most one frame is in
    // flight, and the next frame is only grabbed after the previous decode
    // has completed. No pixel work happens on the UI isolate here — the raw
    // RGB buffer goes straight to the native SDK, which processes it on its
    // own worker threads.
    if (!_isCapturing && _sdkReady) {
      _isCapturing = true;
      try {
        final frame = await _camera.captureFrame(byteOrder: _byteOrder);
        final source = _RgbFrame.fromCameraFrame(frame, rotation: _rotation);
        if (source != null) {
          final response = await _vision.captureBuffer(
            VisionImageBuffer(
              bytes: source.rgb,
              width: source.width,
              height: source.height,
              stride: source.width * 3,
              pixelFormat: VisionPixelFormat.rgb888,
            ),
            _currentRequest(),
          );
          if (_shouldCapture && mounted) {
            setState(() {
              _lastFrame = source;
              _frameWidth = source.width;
              _frameHeight = source.height;
              _result = response;
            });
          }
        }
      } catch (_) {
        // A frame may be unavailable while the camera is starting or stopping.
      } finally {
        _isCapturing = false;
      }
    }
    if (_shouldCapture) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (_shouldCapture) unawaited(_captureLoop());
    }
  }

  CaptureVisionRequest _currentRequest() =>
      CaptureVisionRequest.forTasks([_mode.task]);

  Future<void> _scanImageFile() async {
    if (!_sdkReady || _isPickingImage) return;
    await _stopCamera();
    setState(() => _isPickingImage = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final frame = await _RgbFrame.fromFile(file);
      final request = _currentRequest();
      final result = kIsWeb || file.path.isEmpty
          ? await _vision.captureBuffer(
              VisionImageBuffer(
                bytes: frame.rgb,
                width: frame.width,
                height: frame.height,
                stride: frame.width * 3,
                pixelFormat: VisionPixelFormat.rgb888,
              ),
              request,
            )
          : await _vision.captureFile(file.path, request);
      if (!mounted) return;
      setState(() {
        _lastFrame = frame;
        _frameWidth = frame.width;
        _frameHeight = frame.height;
        _result = result;
      });
      if (_mode == _VisionMode.document &&
          result.documentDetections.isNotEmpty) {
        await _openDocumentEditor(frame, result.documentDetections.first);
      }
    } catch (error) {
      _showMessage('Could not scan the selected image: $error');
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _captureDocument() async {
    final frame = _lastFrame;
    if (frame == null) {
      _showMessage('Wait for a camera frame before capturing the document.');
      return;
    }
    await _stopCamera();
    final detections = _result?.documentDetections ?? const [];
    await _openDocumentEditor(
      frame,
      detections.isEmpty ? null : detections.first,
    );
  }

  Future<void> _openDocumentEditor(
    _RgbFrame frame,
    DocumentDetectionResult? detection,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DocumentEditorPage(frame: frame, detection: detection),
    ),
  );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dynamsoft Capture Vision'),
      actions: [
        IconButton(
          tooltip: 'Scan an image file',
          onPressed: _isPickingImage ? null : _scanImageFile,
          icon: const Icon(Icons.image_outlined),
        ),
      ],
    ),
    // Fixed layout regions: the mode selector, the result panel and the
    // control row all have fixed heights, so the camera preview keeps a
    // stable size while results stream in. Result text scrolls inside its
    // own region instead of squeezing the preview.
    body: Column(
      children: [
        _buildModeSelector(),
        if (_sdkError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _sdkError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(child: _buildPreview()),
        const Divider(height: 1),
        _ResultPanel(mode: _mode, result: _result, status: _sceneStatus),
        _buildControls(),
      ],
    ),
  );

  Widget _buildModeSelector() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: RadioGroup<_VisionMode>(
      groupValue: _mode,
      onChanged: (value) {
        if (value != null && !_cameraOpened) _selectMode(value);
      },
      // One row keeps the selector compact and leaves more room for the
      // camera preview.
      child: Row(
        children: [
          for (final mode in _VisionMode.values)
            Expanded(
              child: InkWell(
                onTap: _cameraOpened ? null : () => _selectMode(mode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Radio<_VisionMode>(value: mode),
                      Flexible(
                        child: Text(
                          mode.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  void _selectMode(_VisionMode mode) {
    setState(() {
      _mode = mode;
      _result = null;
      // MRZ characters are small; the recognition models need
      // high-resolution frames, so default to 1080p for that mode.
      if (_mode == _VisionMode.mrz) {
        _preset = ResolutionPreset.veryHigh;
      }
    });
    unawaited(_runSampleScene());
  }

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Row(
      children: [
        // Icon-only controls: the row stays compact even with the resolution
        // picker and the document capture button beside it.
        IconButton.filled(
          tooltip: _cameraOpened ? 'Stop camera' : 'Start camera',
          onPressed: _cameraOpened ? _stopCamera : _startCamera,
          icon: Icon(_cameraOpened ? Icons.stop : Icons.play_arrow),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: DropdownButton<ResolutionPreset>(
              value: _preset,
              underline: const SizedBox.shrink(),
              isExpanded: true,
              items: [
                for (final preset in ResolutionPreset.values)
                  DropdownMenuItem(
                    value: preset,
                    child: Text(
                      '${preset.name} (${preset.width}x${preset.height})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (preset) {
                if (preset == null) return;
                unawaited(_applyResolution(preset));
              },
            ),
          ),
        ),
        if (_mode == _VisionMode.document) ...[
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: 'Capture document',
            onPressed: _lastFrame == null ? null : _captureDocument,
            icon: const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ],
    ),
  );

  Widget _buildPreview() {
    if (_textureId < 0 && _lastFrame == null) {
      return const Center(
        child: Text('Start the camera or choose an image file.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _frameWidth > 0 ? _frameWidth : 4;
        final height = _frameHeight > 0 ? _frameHeight : 3;
        // The live texture and the frozen camera frame both show the raw
        // unrotated sensor buffer, so both need the same platform rotation.
        // Frames from the sample scene or the gallery are already upright.
        final rotation = _textureId >= 0
            ? _rotation
            : (_lastFrame?.rotation ?? 0);
        final rotated = rotation % 180 == 90;
        // Cover-fit: scale the frame until it fills the whole widget, then
        // clip the overflow. The preview never letterboxes.
        final frameW = rotated ? height : width;
        final frameH = rotated ? width : height;
        final scale = (constraints.maxWidth / frameW).clamp(
          constraints.maxHeight / frameH,
          double.infinity,
        );
        final drawWidth = frameW * scale;
        final drawHeight = frameH * scale;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: drawWidth,
              height: drawHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RotatedBox(
                    quarterTurns: (rotation ~/ 90) % 4,
                    child: _textureId >= 0
                        ? _camera.buildPreview(_textureId)
                        : Image.memory(_lastFrame!.pngBytes, fit: BoxFit.fill),
                  ),
                  CustomPaint(
                    painter: _VisionOverlayPainter(
                      mode: _mode,
                      result: _result,
                      sourceWidth: width,
                      sourceHeight: height,
                      rotation: rotation,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.mode, required this.result, this.status});

  final _VisionMode mode;
  final CaptureVisionResult? result;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final text = result == null
        ? (status ?? '')
        : switch (mode) {
            _VisionMode.barcode =>
              result!.barcodes.isEmpty
                  ? 'No barcode found.'
                  : result!.barcodes
                        .take(2)
                        .map((item) => '${item.format}: ${item.text}')
                        .join('\n'),
            _VisionMode.mrz =>
              result!.mrzResults.isEmpty
                  ? 'No MRZ found.'
                  : result!.mrzResults
                        .take(1)
                        .map(
                          (item) => item.rawText.isEmpty
                              ? item.fields.values.join('\n')
                              : item.rawText,
                        )
                        .join('\n'),
            _VisionMode.document =>
              '${result!.documentDetections.length} document '
                  'boundaries found.',
          };
    // A fixed height keeps the camera preview above stable no matter how
    // much text a result contains; overflowing text scrolls inside.
    return Container(
      width: double.infinity,
      height: 120,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(child: SelectableText(text)),
    );
  }
}

class _DocumentEditorPage extends StatefulWidget {
  const _DocumentEditorPage({required this.frame, this.detection});

  final _RgbFrame frame;
  final DocumentDetectionResult? detection;

  @override
  State<_DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<_DocumentEditorPage> {
  late DocumentCorners _corners;
  late DocumentExport _sourcePreview;
  late DocumentExport _rendered;
  DocumentFilter _filter = DocumentFilter.color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _corners = _cornersFor(widget.frame, widget.detection);
    _sourcePreview = _export(
      DocumentFilter.color,
      _fullFrameCorners(widget.frame),
    );
    _rendered = _export(_filter, _corners);
  }

  DocumentExport _export(DocumentFilter filter, DocumentCorners corners) =>
      DocumentExporter.exportRgb(
        rgb: widget.frame.rgb,
        width: widget.frame.width,
        height: widget.frame.height,
        corners: corners,
        filter: filter,
      );

  void _setCorner(int index, DocumentPoint point) {
    final bounded = DocumentPoint(
      point.x.clamp(0, (widget.frame.width - 1).toDouble()).toDouble(),
      point.y.clamp(0, (widget.frame.height - 1).toDouble()).toDouble(),
    );
    setState(() {
      _corners = _corners.replace(index, bounded);
      _rendered = _export(_filter, _corners);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final path = await FileSaver.instance.saveFile(
        name:
            'capture_vision_document_${DateTime.now().millisecondsSinceEpoch}',
        bytes: _rendered.pngBytes,
        fileExtension: 'png',
        mimeType: MimeType.png,
      );
      if (mounted) _showMessage('Saved document to $path');
    } catch (error) {
      if (mounted) _showMessage('Could not save the document: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Document captured with Dynamsoft Capture Vision '
              '(${_rendered.width} × ${_rendered.height}).',
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('Could not open sharing: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit document')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Drag the four handles to adjust the document boundary.',
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.frame.width / widget.frame.height,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_sourcePreview.pngBytes, fit: BoxFit.fill),
                      CustomPaint(
                        painter: _DocumentCornersPainter(
                          corners: _corners,
                          sourceWidth: widget.frame.width,
                          sourceHeight: widget.frame.height,
                        ),
                      ),
                      for (var index = 0; index < 4; index++)
                        _DocumentHandle(
                          point: _corners.points[index],
                          index: index,
                          sourceWidth: widget.frame.width,
                          sourceHeight: widget.frame.height,
                          displayWidth: constraints.maxWidth,
                          displayHeight: constraints.maxHeight,
                          onMove: _setCorner,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final filter in DocumentFilter.values)
                ChoiceChip(
                  label: Text(_filterLabel(filter)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() {
                    _filter = filter;
                    _rendered = _export(_filter, _corners);
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 110,
              child: Image.memory(_rendered.pngBytes, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_alt),
                    label: Text(_saving ? 'Saving…' : 'Export & save PNG'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DocumentHandle extends StatelessWidget {
  const _DocumentHandle({
    required this.point,
    required this.index,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.displayWidth,
    required this.displayHeight,
    required this.onMove,
  });

  final DocumentPoint point;
  final int index;
  final int sourceWidth;
  final int sourceHeight;
  final double displayWidth;
  final double displayHeight;
  final void Function(int index, DocumentPoint point) onMove;

  @override
  Widget build(BuildContext context) => Positioned(
    left: point.x / sourceWidth * displayWidth - 16,
    top: point.y / sourceHeight * displayHeight - 16,
    child: GestureDetector(
      onPanUpdate: (details) => onMove(
        index,
        DocumentPoint(
          point.x + details.delta.dx / displayWidth * sourceWidth,
          point.y + details.delta.dy / displayHeight * sourceHeight,
        ),
      ),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    ),
  );
}

class _VisionOverlayPainter extends CustomPainter {
  const _VisionOverlayPainter({
    required this.mode,
    required this.result,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.rotation,
  });

  final _VisionMode mode;
  final CaptureVisionResult? result;
  final int sourceWidth;
  final int sourceHeight;
  final int rotation;

  /// Maps a point from source-frame coordinates onto the display canvas,
  /// applying the same clockwise rotation as the preview widget.
  Offset _transform(double x, double y, Size size) {
    final double nx;
    final double ny;
    switch ((rotation ~/ 90) % 4) {
      case 1: // 90° clockwise: canvas becomes sourceHeight x sourceWidth
        nx = sourceHeight - y;
        ny = x;
      case 2: // 180°
        nx = sourceWidth - x;
        ny = sourceHeight - y;
      case 3: // 270° clockwise
        nx = y;
        ny = sourceWidth - x;
      default: // 0°
        nx = x;
        ny = y;
    }
    final double canvasW;
    final double canvasH;
    if ((rotation ~/ 90) % 2 == 1) {
      canvasW = sourceHeight.toDouble();
      canvasH = sourceWidth.toDouble();
    } else {
      canvasW = sourceWidth.toDouble();
      canvasH = sourceHeight.toDouble();
    }
    return Offset(nx / canvasW * size.width, ny / canvasH * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (result == null || sourceWidth <= 0 || sourceHeight <= 0) return;
    final locations = switch (mode) {
      _VisionMode.barcode => result!.barcodes.map((item) => item.location),
      _VisionMode.mrz =>
        result!.mrzResults
            .map((item) => item.location)
            .whereType<VisionQuadrilateral>(),
      _VisionMode.document => result!.documentDetections.map(
        (item) => item.location,
      ),
    };
    final paint = Paint()
      ..color = mode == _VisionMode.document
          ? Colors.tealAccent
          : Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final location in locations) {
      final path = Path();
      for (var index = 0; index < location.points.length; index++) {
        final point = location.points[index];
        final offset = _transform(point.x, point.y, size);
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisionOverlayPainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.result != result ||
      oldDelegate.sourceWidth != sourceWidth ||
      oldDelegate.sourceHeight != sourceHeight ||
      oldDelegate.rotation != rotation;
}

class _DocumentCornersPainter extends CustomPainter {
  const _DocumentCornersPainter({
    required this.corners,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final DocumentCorners corners;
  final int sourceWidth;
  final int sourceHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var index = 0; index < corners.points.length; index++) {
      final point = corners.points[index];
      final offset = Offset(
        point.x / sourceWidth * size.width,
        point.y / sourceHeight * size.height,
      );
      if (index == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.lightGreenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _DocumentCornersPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.sourceWidth != sourceWidth ||
      oldDelegate.sourceHeight != sourceHeight;
}

class _RgbFrame {
  _RgbFrame({
    required this.rgb,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  final Uint8List rgb;
  final int width;
  final int height;

  /// Clockwise degrees (0/90/180/270) to rotate the raw buffer so it displays
  /// upright. Camera frames carry the rotation reported by the camera plugin
  /// (iOS sensors deliver landscape buffers); sample scenes and picked files
  /// are already upright.
  final int rotation;

  Uint8List? _pngBytes;

  /// PNG encoding is pure-Dart and takes hundreds of milliseconds for a
  /// 1080p frame, so it is never done while the camera is running. It runs
  /// once, lazily, when the still frame actually needs to be displayed
  /// (after the camera stops or for the document editor). The bytes are
  /// copied first: on web the recognition pipeline can detach the original
  /// buffer once it has been handed to the SDK.
  Uint8List get pngBytes => _pngBytes ??= Uint8List.fromList(
    image.encodePng(
      image.Image.fromBytes(
        width: width,
        height: height,
        bytes: Uint8List.fromList(rgb).buffer,
        numChannels: 3,
      ),
    ),
  );

  static _RgbFrame fromSample(SampleImage sample) =>
      _RgbFrame(rgb: sample.rgb, width: sample.width, height: sample.height);

  static _RgbFrame? fromCameraFrame(
    Map<String, dynamic> values, {
    int rotation = 0,
  }) {
    final bytes = values['data'];
    final width = values['width'];
    final height = values['height'];
    if (bytes is! Uint8List ||
        width is! int ||
        height is! int ||
        bytes.lengthInBytes < width * height * 3) {
      return null;
    }
    // Keep the raw RGB buffer only; encoding happens lazily via pngBytes.
    return _RgbFrame(
      rgb: bytes,
      width: width,
      height: height,
      rotation: rotation,
    );
  }

  static Future<_RgbFrame> fromFile(XFile file) async {
    final decoded = image.decodeImage(await file.readAsBytes());
    if (decoded == null) {
      throw StateError('The selected file is not a supported image.');
    }
    return _RgbFrame(
      rgb: decoded.getBytes(order: image.ChannelOrder.rgb),
      width: decoded.width,
      height: decoded.height,
    );
  }
}

DocumentCorners _cornersFor(
  _RgbFrame frame,
  DocumentDetectionResult? detection,
) {
  final points = detection?.location.points;
  if (points != null && points.length == 4) {
    return DocumentCorners(
      topLeft: DocumentPoint(points[0].x, points[0].y),
      topRight: DocumentPoint(points[1].x, points[1].y),
      bottomRight: DocumentPoint(points[2].x, points[2].y),
      bottomLeft: DocumentPoint(points[3].x, points[3].y),
    );
  }
  return _fullFrameCorners(frame);
}

DocumentCorners _fullFrameCorners(_RgbFrame frame) => DocumentCorners(
  topLeft: const DocumentPoint(0, 0),
  topRight: DocumentPoint((frame.width - 1).toDouble(), 0),
  bottomRight: DocumentPoint(
    (frame.width - 1).toDouble(),
    (frame.height - 1).toDouble(),
  ),
  bottomLeft: DocumentPoint(0, (frame.height - 1).toDouble()),
);

String _filterLabel(DocumentFilter filter) => switch (filter) {
  DocumentFilter.color => 'Color',
  DocumentFilter.grayscale => 'Grayscale',
  DocumentFilter.blackAndWhite => 'B/W',
};
