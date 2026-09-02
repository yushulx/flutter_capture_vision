import DynamsoftMRZScannerBundle
import Flutter
import UIKit

/// iOS bridge for the unified Capture Vision API.
///
/// Every DCV interaction is confined to `workerQueue`. Capture Vision routers
/// have mutable template state, so serializing lifecycle, settings and capture
/// calls avoids both UI blocking and a template reset racing a camera frame.
public final class FlutterCaptureVisionPlugin: NSObject, FlutterPlugin,
    LicenseVerificationListener {
  private let workerQueue = DispatchQueue(
    label: "com.dynamsoft.flutter_capture_vision.worker")
  private var router: CaptureVisionRouter?
  private var initialized = false
  private var pendingLicenseResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_capture_vision", binaryMessenger: registrar.messenger())
    let instance = FlutterCaptureVisionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let method = call.method
    let arguments = call.arguments as? [String: Any] ?? [:]

    if method == "initialize" {
      workerQueue.async { [weak self] in
        guard let self = self else { return }
        do {
          let licenseKey = try self.requiredString(arguments, key: "licenseKey")
          self.pendingLicenseResult = result
          LicenseManager.initLicense(licenseKey, verificationDelegate: self)
        } catch {
          self.complete(result, error: error)
        }
      }
      return
    }

    workerQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        switch method {
        case "initSettings":
          try self.requireRouter().initSettings(
            self.requiredString(arguments, key: "settingsJson"))
          self.complete(result, value: nil)
        case "resetSettings":
          try self.requireRouter().resetSettings()
          self.complete(result, value: nil)
        case "captureFile":
          let path = try self.requiredString(arguments, key: "path")
          let captured = try self.captureFile(path, templates: try self.templates(arguments))
          self.complete(result, value: captured)
        case "captureBuffer":
          let captured = try self.captureBuffer(arguments)
          self.complete(result, value: captured)
        case "dispose":
          self.initialized = false
          self.router = nil
          self.complete(result, value: nil)
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
      } catch {
        self.complete(result, error: error)
      }
    }
  }

  public func onLicenseVerified(_ isSuccess: Bool, error: Error?) {
    workerQueue.async { [weak self] in
      guard let self = self, let completion = self.pendingLicenseResult else { return }
      self.pendingLicenseResult = nil
      if isSuccess {
        self.router = CaptureVisionRouter()
        self.initialized = true
        self.complete(completion, value: nil)
      } else {
        self.complete(completion, error: VisionBridgeError(
          code: "license_error",
          message: error?.localizedDescription ?? "Unable to initialize the Dynamsoft license."))
      }
    }
  }

  private func captureFile(_ path: String, templates: [String]) throws -> [String: Any] {
    let router = try requireRouter()
    var output = emptyResult()
    for template in templates {
      try append(router.captureFromFile(path, templateName: template), to: &output, template: template)
    }
    return output
  }

  private func captureBuffer(_ arguments: [String: Any]) throws -> [String: Any] {
    let buffer = try requiredMap(arguments, key: "buffer")
    guard let typedData = buffer["bytes"] as? FlutterStandardTypedData else {
      throw VisionBridgeError(code: "invalid_argument", message: "Buffer bytes must be Uint8List.")
    }
    // The typed channel payload is copied before being held by an asynchronous
    // DCV operation, so it never relies on Flutter's message buffer lifetime.
    let bytes = Data(typedData.data)
    let width = try requiredInt(buffer, key: "width")
    let height = try requiredInt(buffer, key: "height")
    let stride = try requiredInt(buffer, key: "stride")
    let rotation = try requiredInt(buffer, key: "rotation")
    if bytes.isEmpty || width <= 0 || height <= 0 || stride <= 0 {
      throw VisionBridgeError(code: "invalid_argument", message: "The image buffer has invalid geometry.")
    }
    let image = ImageData(
      bytes: bytes,
      width: UInt(width),
      height: UInt(height),
      stride: UInt(stride),
      format: try pixelFormat(try requiredString(buffer, key: "pixelFormat")),
      orientation: rotation,
      tag: nil)

    let router = try requireRouter()
    var output = emptyResult()
    for template in try templates(arguments) {
      try append(router.captureFromBuffer(image, templateName: template), to: &output, template: template)
    }
    return output
  }

  private func append(_ captured: CapturedResult, to output: inout [String: Any], template: String) throws {
    if captured.errorCode != 0 {
      throw VisionBridgeError(
        code: String(captured.errorCode),
        message: captured.errorMessage ?? "DCV capture failed for template '\(template)'.")
    }

    var barcodes = output["barcodes"] as! [[String: Any]]
    for item in captured.decodedBarcodesResult?.items ?? [] {
      barcodes.append([
        "format": item.formatString,
        "text": item.text,
        "rawBytes": item.bytes,
        "confidence": Int(item.confidence),
        "location": quadrilateral(item.location),
      ])
    }
    output["barcodes"] = barcodes

    var mrzResults = output["mrzResults"] as! [[String: Any]]
    for item in captured.parsedResult?.items ?? [] {
      let fields = item.parsedFields
      let lines = ["line1", "line2", "line3"].compactMap { fields[$0] }.filter { !$0.isEmpty }
      mrzResults.append([
        "rawText": lines.joined(separator: "\n"),
        "documentType": item.codeType,
        "fields": fields,
      ])
    }
    // The parsed item itself carries no geometry. The MRZ zone is the union
    // of the recognized text-line quads, attached here so overlays can
    // highlight the zone; when the parser produced nothing (low resolution or
    // a damaged zone) the raw lines become the result.
    let lineItems = captured.recognizedTextLinesResult?.items ?? []
    var zonePoints: [CGPoint] = []
    var rawLines: [String] = []
    var lowestConfidence = Int.max
    for line in lineItems {
      if !line.text.isEmpty { rawLines.append(line.text) }
      for value in line.location.points {
        zonePoints.append(value.cgPointValue)
      }
      lowestConfidence = min(lowestConfidence, line.confidence)
    }
    let mrzZone = quadrilateralFromPoints(zonePoints)
    if !mrzResults.isEmpty {
      if let zone = mrzZone { mrzResults[0]["location"] = zone }
      if lowestConfidence != Int.max { mrzResults[0]["confidence"] = lowestConfidence }
    } else if let zone = mrzZone, !rawLines.isEmpty {
      mrzResults.append([
        "rawText": rawLines.joined(separator: "\n"),
        "documentType": "",
        "fields": [String: String](),
        "confidence": lowestConfidence == Int.max ? 0 : lowestConfidence,
        "location": zone,
      ])
    }
    output["mrzResults"] = mrzResults

    var detections = output["documentDetections"] as! [[String: Any]]
    for item in captured.processedDocumentResult?.detectedQuadResultItems ?? [] {
      detections.append([
        "confidence": Int(item.confidenceAsDocumentBoundary),
        "location": quadrilateral(item.location),
      ])
    }
    output["documentDetections"] = detections
  }

  private func emptyResult() -> [String: Any] {
    ["barcodes": [[String: Any]](), "mrzResults": [[String: Any]](),
     "documentDetections": [[String: Any]]()]
  }

  private func quadrilateral(_ value: Quadrilateral) -> [String: Any] {
    let points = value.points.map { pointValue -> [String: Any] in
      let point = pointValue.cgPointValue
      return ["x": Double(point.x), "y": Double(point.y)]
    }
    return ["points": points]
  }

  /// The MRZ zone: the union of the recognized text-line quads.
  private func quadrilateralFromPoints(_ zonePoints: [CGPoint]) -> [String: Any]? {
    guard !zonePoints.isEmpty else { return nil }
    var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
    for point in zonePoints {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }
    let corners = [
      ["x": Double(minX), "y": Double(minY)],
      ["x": Double(maxX), "y": Double(minY)],
      ["x": Double(maxX), "y": Double(maxY)],
      ["x": Double(minX), "y": Double(maxY)],
    ]
    return ["points": corners]
  }

  private func templates(_ arguments: [String: Any]) throws -> [String] {
    let request = try requiredMap(arguments, key: "request")
    switch try requiredString(request, key: "type") {
    case "template":
      return [try requiredString(request, key: "templateName")]
    case "tasks":
      guard let tasks = request["tasks"] as? [String], !tasks.isEmpty else {
        throw VisionBridgeError(code: "invalid_argument", message: "A task request requires at least one task.")
      }
      return try tasks.map {
        switch $0 {
        case "barcode": return "ReadBarcodes_Default"
        case "mrz": return "ReadPassportAndId"
        case "documentDetection": return "DetectDocumentBoundaries_Default"
        default:
          throw VisionBridgeError(code: "invalid_argument", message: "Unknown Capture Vision task: \($0)")
        }
      }
    default:
      throw VisionBridgeError(code: "invalid_argument", message: "Request type must be 'tasks' or 'template'.")
    }
  }

  private func requireRouter() throws -> CaptureVisionRouter {
    guard initialized, let router = router else {
      throw VisionBridgeError(code: "not_initialized", message: "Call initialize() before using Capture Vision.")
    }
    return router
  }

  private func requiredMap(_ values: [String: Any], key: String) throws -> [String: Any] {
    guard let value = values[key] as? [String: Any] else {
      throw VisionBridgeError(code: "invalid_argument", message: "Missing or invalid map argument: \(key)")
    }
    return value
  }

  private func requiredString(_ values: [String: Any], key: String) throws -> String {
    guard let value = values[key] as? String, !value.isEmpty else {
      throw VisionBridgeError(code: "invalid_argument", message: "Missing or invalid string argument: \(key)")
    }
    return value
  }

  private func requiredInt(_ values: [String: Any], key: String) throws -> Int {
    guard let value = values[key] as? NSNumber else {
      throw VisionBridgeError(code: "invalid_argument", message: "Missing or invalid integer argument: \(key)")
    }
    return value.intValue
  }

  private func pixelFormat(_ value: String) throws -> ImagePixelFormat {
    // The SDK's ObjC enum cases keep their acronym casing after the
    // DSImagePixelFormat prefix is stripped on Swift import.
    switch value {
    case "binary": return .binary
    case "grayscale": return .grayScaled
    case "nv21": return .NV21
    case "rgb565": return .RGB565
    case "rgb555": return .RGB555
    case "rgb888": return .RGB888
    case "argb8888": return .ARGB8888
    case "abgr8888": return .ABGR8888
    case "bgr888": return .BGR888
    case "nv12": return .NV12
    default:
      throw VisionBridgeError(code: "invalid_argument", message: "Unsupported image pixel format: \(value)")
    }
  }

  private func complete(_ result: @escaping FlutterResult, value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func complete(_ result: @escaping FlutterResult, error: Error) {
    let bridgeError = error as? VisionBridgeError
    DispatchQueue.main.async {
      result(FlutterError(
        code: bridgeError?.code ?? "native_error",
        message: bridgeError?.message ?? error.localizedDescription,
        details: nil))
    }
  }
}

private struct VisionBridgeError: LocalizedError {
  let code: String
  let message: String

  var errorDescription: String? { message }
}
