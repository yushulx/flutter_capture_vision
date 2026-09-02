import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_capture_vision_platform_interface/flutter_capture_vision_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'mrz_template.dart';

/// Browser implementation backed by the self-hosted Dynamsoft DCV bundle.
///
/// DCV exposes Promise-based APIs and executes the engine work asynchronously;
/// this implementation deliberately preserves that boundary rather than doing
/// a synchronous JavaScript call from a Flutter frame callback.
///
/// All namespace navigation goes through `Reflect` reads instead of typed
/// interop access: the bundle builds its namespaces as null-prototype
/// objects, which Dart interop type checks (`isA<JSObject>()`) reject.
@JS('Reflect.get')
external JSAny? _getPropertyValue(JSAny? object, JSAny key);

@JS('Reflect.set')
external JSBoolean _setPropertyValue(JSAny? object, JSAny key, JSAny? value);

@JS('Reflect.apply')
external JSAny? _applyFunction(
  JSAny? function,
  JSAny? thisArgument,
  JSArray<JSAny?> arguments,
);

@JS('Object.keys')
external JSArray<JSString> _objectKeysOf(JSAny? object);

class FlutterCaptureVisionWeb extends CaptureVisionPlatform {
  static const _assetRoot =
      'assets/packages/flutter_capture_vision_web/assets/dcv/';
  static const _bundleUrl =
      '${_assetRoot}dynamsoft-capture-vision-bundle@3.6.2000/dist/dcv.bundle.js';

  // The web engine ships no built-in MRZ preset; MRZ captures run through the
  // `ReadMRZ` template from the reference sample, imported lazily, while
  // factory presets are restored before any built-in template capture.
  static const _mrzTemplateName = 'ReadMRZ';

  JSAny? _router;
  JSAny? _codeParser;
  bool _mrzSettingsImported = false;
  Future<void>? _loadFuture;

  /// Registers this implementation with Flutter's web plugin registry.
  static void registerWith(Registrar registrar) {
    CaptureVisionPlatform.instance = FlutterCaptureVisionWeb();
  }

  @override
  Future<void> initialize(String licenseKey) async {
    await _loadSdk();
    final dynamsoft = _requireDynamsoft();
    final licenseManager = _get(_get(dynamsoft, 'License'), 'LicenseManager');
    await _call(licenseManager, 'initLicense', [licenseKey.toJS, true.toJS]);
    // Load the engine modules and register the MRZ parser specifications up
    // front, exactly like the reference web sample; skipping this leaves the
    // Code Parser unlicensed (-90012) and MRZ captures fail.
    final coreModule = _get(_get(dynamsoft, 'Core'), 'CoreModule');
    await _call(coreModule, 'loadWasm', [
      ['DBR', 'DLR', 'DDN'].map((module) => module.toJS).toList().toJS,
    ]);
    final dcp = _get(dynamsoft, 'DCP');
    _codeParser = await _call(
      _get(dcp, 'CodeParser'),
      'createInstance',
      const [],
    );
    final parserModule = _get(dcp, 'CodeParserModule');
    for (final specification in [
      'MRTD_TD1_ID',
      'MRTD_TD2_FRENCH_ID',
      'MRTD_TD2_ID',
      'MRTD_TD2_VISA',
      'MRTD_TD3_PASSPORT',
      'MRTD_TD3_VISA',
    ]) {
      await _call(parserModule, 'loadSpec', [specification.toJS]);
    }
    final routerType = _get(_get(dynamsoft, 'CVR'), 'CaptureVisionRouter');
    // Pre-fetch the MRZ recognition models so the first MRZ capture does not
    // stall, matching the reference web sample.
    await _call(routerType, 'appendDLModelBuffer', ['MRZCharRecognition'.toJS]);
    await _call(routerType, 'appendDLModelBuffer', [
      'MRZTextLineRecognition'.toJS,
    ]);
    final router = await _call(routerType, 'createInstance', const []);
    if (router == null) {
      throw const CaptureVisionException(
        code: 'web_router_creation_failed',
        message: 'The DCV browser SDK did not return a CaptureVisionRouter.',
      );
    }
    _router = router;
  }

  @override
  Future<void> initSettings(String settingsJson) async {
    await _call(_requireRouter(), 'initSettings', [settingsJson.toJS]);
  }

  @override
  Future<void> resetSettings() async {
    await _call(_requireRouter(), 'resetSettings', const []);
  }

  @override
  Future<CaptureVisionResult> captureFile(
    String path,
    CaptureVisionRequest request,
  ) => _capture(
    request,
    (router, template) => _call(router, 'capture', [path.toJS, template.toJS]),
  );

  @override
  Future<CaptureVisionResult> captureBuffer(
    VisionImageBuffer buffer,
    CaptureVisionRequest request,
  ) {
    final imageData = JSObject();
    _set(imageData, 'bytes', buffer.bytes.toJS);
    _set(imageData, 'width', buffer.width.toJS);
    _set(imageData, 'height', buffer.height.toJS);
    _set(imageData, 'stride', buffer.stride.toJS);
    _set(imageData, 'format', _pixelFormatValue(buffer.pixelFormat).toJS);
    _set(imageData, 'orientation', buffer.rotation.degrees.toJS);
    return _capture(
      request,
      (router, template) =>
          _call(router, 'capture', [imageData, template.toJS]),
    );
  }

  @override
  Future<void> dispose() async {
    final router = _router;
    _router = null;
    final parser = _codeParser;
    _codeParser = null;
    if (router != null && _get(router, 'dispose') != null) {
      await _call(router, 'dispose', const []);
    }
    if (parser != null && _get(parser, 'dispose') != null) {
      await _call(parser, 'dispose', const []);
    }
  }

  Future<CaptureVisionResult> _capture(
    CaptureVisionRequest request,
    Future<JSAny?> Function(JSAny? router, String templateName) operation,
  ) async {
    final output = <String, List<Map<String, Object?>>>{
      'barcodes': [],
      'mrzResults': [],
      'documentDetections': [],
    };
    final router = _requireRouter();
    for (final templateName in _templateNamesFor(request)) {
      await _selectSettings(router, templateName);
      final raw = await operation(router, templateName);
      final native = _dartify(raw);
      if (native is! Map) {
        throw const CaptureVisionException(
          code: 'invalid_native_result',
          message: 'The DCV browser SDK returned an invalid capture result.',
        );
      }
      final errorCode = native['errorCode'];
      if (errorCode is num && errorCode != 0) {
        throw CaptureVisionException(
          code: '$errorCode',
          message: native['errorMessage'] as String? ?? 'DCV capture failed.',
        );
      }
      await _appendResult(Map<Object?, Object?>.from(native), raw, output);
    }
    return CaptureVisionResult.fromMap(output);
  }

  /// Switches the router settings between the factory presets and the MRZ
  /// template, mirroring the reference web sample's per-mode behavior.
  Future<void> _selectSettings(JSAny? router, String templateName) async {
    if (templateName == _mrzTemplateName) {
      if (_mrzSettingsImported) return;
      await _call(router, 'initSettings', [mrzTemplateJson.toJS]);
      _mrzSettingsImported = true;
    } else if (_mrzSettingsImported) {
      await _call(router, 'resetSettings', const []);
      _mrzSettingsImported = false;
    }
  }

  static Future<void> _appendResult(
    Map<Object?, Object?> result,
    JSAny? rawResult,
    Map<String, List<Map<String, Object?>>> output,
  ) async {
    final decoded = _map(result['decodedBarcodesResult']);
    for (final item in _list(decoded?['barcodeResultItems'])) {
      final barcode = _map(item);
      if (barcode == null) continue;
      output['barcodes']!.add({
        'format': barcode['formatString'] as String? ?? '',
        'text': barcode['text'] as String? ?? '',
        'rawBytes': _bytes(barcode['bytes']),
        'confidence': barcode['confidence'],
        'location': _quadrilateral(barcode['location']),
      });
    }

    // The composed MRZ text lives in the recognized text lines, and the web
    // SDK's parsed item exposes its fields through accessor methods instead
    // of a `parsedFields` map (the native SDKs return a real map).
    final textLines = _map(result['recognizedTextLinesResult']);
    final lineItems = _list(textLines?['textLineResultItems']);
    final lineTexts = lineItems
        .map((item) => _map(item)?['text'])
        .whereType<String>()
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final parsed = _map(result['parsedResult']);
    for (final item in _list(parsed?['parsedResultItems'])) {
      final parsedItem = _map(item);
      if (parsedItem == null) continue;
      final fields = await _parsedFieldsOf(
        _get(_get(rawResult, 'parsedResult'), 'parsedResultItems'),
        parsedItem['codeType'] as String? ?? '',
      );
      final lines = lineTexts.isNotEmpty
          ? lineTexts.join('\n')
          : ['line1', 'line2', 'line3']
                .map((name) => fields[name])
                .whereType<String>()
                .where((line) => line.isNotEmpty)
                .join('\n');
      output['mrzResults']!.add({
        'rawText': lines,
        'documentType': parsedItem['codeType'] as String? ?? '',
        'fields': fields,
        if (lineItems.isNotEmpty)
          'location': _quadrilateral(_map(lineItems.first)?['location']),
        if (lineItems.isNotEmpty)
          'confidence': _map(lineItems.first)?['confidence'],
      });
    }
    // Fall back to the recognized raw text lines when the parser produced
    // nothing (low resolution or a damaged zone).
    if (output['mrzResults']!.isEmpty && lineTexts.isNotEmpty) {
      output['mrzResults']!.add({
        'rawText': lineTexts.join('\n'),
        'documentType': '',
        'fields': const <String, String>{},
        'location': _quadrilateral(_map(lineItems.first)?['location']),
        'confidence': _map(lineItems.first)?['confidence'],
      });
    }

    final documents = _map(result['processedDocumentResult']);
    for (final item in _list(documents?['detectedQuadResultItems'])) {
      final detection = _map(item);
      if (detection == null) continue;
      output['documentDetections']!.add({
        'confidence': detection['confidenceAsDocumentBoundary'],
        'location': _quadrilateral(detection['location']),
      });
    }
  }

  Future<void> _loadSdk() => _loadFuture ??= _loadSdkOnce();

  Future<void> _loadSdkOnce() async {
    if (!_hasDynamsoft()) {
      final completion = Completer<void>();
      final script = web.HTMLScriptElement()
        ..async = true
        ..src = _bundleUrl;
      script.addEventListener(
        'load',
        ((web.Event _) => completion.complete()).toJS,
      );
      script.addEventListener(
        'error',
        ((web.Event _) => completion.completeError(
          const CaptureVisionException(
            code: 'web_sdk_load_failed',
            message: 'Unable to load the self-hosted Dynamsoft DCV bundle.',
          ),
        )).toJS,
      );
      web.document.head!.append(script);
      await completion.future;
    }
    // The bundle normally attaches its namespaces synchronously on the script
    // `load` event, but under debug module loaders the UMD factory can settle
    // a moment later, so poll briefly instead of failing on the first read.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      final paths = _engineResourcePaths();
      if (paths != null) {
        // DCV's internal resource resolution derives its versioned engine/data
        // directories from this root. The packaged assets mirror that layout.
        _set(paths, 'rootDirectory', _assetRoot.toJS);
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const CaptureVisionException(
          code: 'web_sdk_load_failed',
          message:
              'The Dynamsoft DCV browser bundle loaded but never exposed its '
              'Core namespace.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// The `Core.CoreModule.engineResourcePaths` object, or null until the
  /// bundle has fully attached its namespaces to `window.Dynamsoft`.
  JSAny? _engineResourcePaths() {
    final dynamsoft = _get(globalContext, 'Dynamsoft');
    if (dynamsoft == null) return null;
    final core = _get(dynamsoft, 'Core');
    if (core == null) return null;
    final coreModule = _get(core, 'CoreModule');
    if (coreModule == null) return null;
    return _get(coreModule, 'engineResourcePaths');
  }

  JSAny? _requireDynamsoft() {
    final dynamsoft = _get(globalContext, 'Dynamsoft');
    if (dynamsoft == null) {
      throw const CaptureVisionException(
        code: 'web_sdk_not_loaded',
        message: 'The Dynamsoft DCV browser bundle is not available.',
      );
    }
    return dynamsoft;
  }

  bool _hasDynamsoft() => _get(globalContext, 'Dynamsoft') != null;

  JSAny? _requireRouter() {
    final router = _router;
    if (router == null) {
      throw const CaptureVisionException(
        code: 'not_initialized',
        message: 'Call initialize() before using Capture Vision on the web.',
      );
    }
    return router;
  }

  /// Reads a property through Reflect.get, which works on every object shape.
  static JSAny? _get(JSAny? object, String key) =>
      _getPropertyValue(object, key.toJS);

  /// Writes a property through Reflect.set, which works on every object shape.
  static void _set(JSAny? object, String key, JSAny? value) {
    _setPropertyValue(object, key.toJS, value);
  }

  /// Invokes a JS function with [thisArgument] bound and awaits the result
  /// when it is a promise.
  static Future<JSAny?> _call(
    JSAny? target,
    String method,
    List<JSAny?> arguments,
  ) async {
    final function = _get(target, method);
    if (function == null) {
      throw CaptureVisionException(
        code: 'web_method_missing',
        message: 'The Dynamsoft DCV browser bundle does not expose `$method`.',
      );
    }
    final value = _applyFunction(function, target, arguments.toJS);
    if (value != null && value.isA<JSPromise<JSAny?>>()) {
      return (value as JSPromise<JSAny?>).toDart;
    }
    return value;
  }

  static Object? _dartify(JSAny? value) {
    if (value == null || value.isUndefinedOrNull) return null;
    if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
    if (value.isA<JSNumber>()) {
      final number = (value as JSNumber).toDartDouble;
      return number == number.truncateToDouble() ? number.toInt() : number;
    }
    if (value.isA<JSString>()) return (value as JSString).toDart;
    if (value.isA<JSUint8Array>()) return (value as JSUint8Array).toDart;
    if (value.isA<JSArray>()) {
      final array = value as JSArray<JSAny?>;
      return List<Object?>.generate(
        array.length,
        (index) => _dartify(array[index]),
      );
    }
    if (value.typeofEquals('object')) {
      // Plain objects, including the null-prototype namespaces the bundle
      // builds with Object.create(null).
      final map = <String, Object?>{};
      final keys = _objectKeysOf(value);
      for (var index = 0; index < keys.length; index++) {
        final key = keys[index].toDart;
        map[key] = _dartify(_get(value, key));
      }
      return map;
    }
    return null;
  }

  /// Reads the MRZ fields from a web SDK parsed item. The web bundle exposes
  /// `getAllFieldNames()` / `getFieldValue(name)` methods instead of the
  /// `parsedFields` map returned by the native SDKs.
  static Future<Map<String, String>> _parsedFieldsOf(
    JSAny? parsedItems,
    String codeType,
  ) async {
    final fields = <String, String>{};
    if (parsedItems == null || !parsedItems.isA<JSArray>()) {
      return fields;
    }
    final itemArray = parsedItems as JSArray;
    // One parsed item per document; take the first that parses.
    for (var index = 0; index < itemArray.length; index++) {
      final item = itemArray[index];
      final names = await _call(item, 'getAllFieldNames', const []);
      if (names == null || !names.isA<JSArray>()) continue;
      final nameArray = names as JSArray;
      for (var nameIndex = 0; nameIndex < nameArray.length; nameIndex++) {
        final name = (nameArray[nameIndex] as JSString).toDart;
        final value = await _call(item, 'getFieldValue', [name.toJS]);
        if (value != null && value.isA<JSString>()) {
          final text = (value as JSString).toDart;
          if (text.isNotEmpty) fields[name] = text;
        }
      }
      if (fields.isNotEmpty || codeType.isNotEmpty) return fields;
    }
    return fields;
  }

  static Map<Object?, Object?>? _map(Object? value) =>
      value is Map ? Map<Object?, Object?>.from(value) : null;

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const [];

  static Uint8List? _bytes(Object? value) => value is Uint8List
      ? value
      : value is List
      ? Uint8List.fromList(
          value.whereType<num>().map((item) => item.toInt()).toList(),
        )
      : null;

  static Map<String, Object?> _quadrilateral(Object? value) {
    final quad = _map(value);
    final points = _list(quad?['points'])
        .map((point) {
          final map = _map(point);
          return <String, Object?>{'x': map?['x'], 'y': map?['y']};
        })
        .toList(growable: false);
    return {'points': points};
  }

  static int _pixelFormatValue(VisionPixelFormat format) => switch (format) {
    VisionPixelFormat.binary => 0,
    VisionPixelFormat.grayscale => 2,
    VisionPixelFormat.nv21 => 3,
    VisionPixelFormat.rgb565 => 4,
    VisionPixelFormat.rgb555 => 5,
    VisionPixelFormat.rgb888 => 6,
    VisionPixelFormat.argb8888 => 7,
    VisionPixelFormat.abgr8888 => 10,
    VisionPixelFormat.bgr888 => 12,
    VisionPixelFormat.nv12 => 14,
  };

  static List<String> _templateNamesFor(CaptureVisionRequest request) =>
      switch (request) {
        NamedTemplateCaptureVisionRequest() => [request.templateName],
        DefaultTasksCaptureVisionRequest() =>
          request.tasks
              .map(
                (task) => task == VisionTask.mrz
                    ? _mrzTemplateName
                    : task.defaultTemplateName,
              )
              .toList(growable: false),
      };
}
