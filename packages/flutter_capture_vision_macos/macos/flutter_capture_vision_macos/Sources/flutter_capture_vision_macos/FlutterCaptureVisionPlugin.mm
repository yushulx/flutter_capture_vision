#import "FlutterCaptureVisionPlugin.h"

#include "vision_router.h"

using flutter_capture_vision::VisionError;
using flutter_capture_vision::VisionQuadrilateral;
using flutter_capture_vision::VisionResult;
using flutter_capture_vision::VisionRouter;

namespace {

NSString* const kChannelName = @"flutter_capture_vision";

NSString* RequiredString(NSDictionary* map, NSString* key) {
  id value = map[key];
  if (![value isKindOfClass:[NSString class]]) {
    throw VisionError(-1, "Missing or invalid string argument.");
  }
  return value;
}

NSInteger RequiredInteger(NSDictionary* map, NSString* key) {
  id value = map[key];
  if (![value isKindOfClass:[NSNumber class]]) {
    throw VisionError(-1, "Missing or invalid integer argument.");
  }
  return [value integerValue];
}

NSDictionary* RequiredMap(NSDictionary* map, NSString* key) {
  id value = map[key];
  if (![value isKindOfClass:[NSDictionary class]]) {
    throw VisionError(-1, "Missing or invalid map argument.");
  }
  return value;
}

std::vector<std::string> TemplatesForRequest(NSDictionary* arguments) {
  NSDictionary* request = RequiredMap(arguments, @"request");
  NSString* type = RequiredString(request, @"type");
  if ([type isEqualToString:@"template"]) {
    return {std::string([RequiredString(request, @"templateName") UTF8String])};
  }
  if (![type isEqualToString:@"tasks"]) {
    throw VisionError(-1, "Request type must be 'tasks' or 'template'.");
  }
  id values = request[@"tasks"];
  if (![values isKindOfClass:[NSArray class]] || [values count] == 0) {
    throw VisionError(-1, "A task request requires at least one task.");
  }
  std::vector<std::string> templates;
  for (id value in (NSArray*)values) {
    if (![value isKindOfClass:[NSString class]]) {
      throw VisionError(-1, "Every task must be a string.");
    }
    NSString* task = (NSString*)value;
    if ([task isEqualToString:@"barcode"]) templates.emplace_back("ReadBarcodes_Default");
    else if ([task isEqualToString:@"mrz"]) templates.emplace_back("ReadPassportAndId");
    else if ([task isEqualToString:@"documentDetection"]) templates.emplace_back("DetectDocumentBoundaries_Default");
    else throw VisionError(-1, "Unknown Capture Vision task.");
  }
  return templates;
}

NSDictionary* QuadrilateralMap(const VisionQuadrilateral& location) {
  NSMutableArray* points = [NSMutableArray arrayWithCapacity:4];
  for (NSUInteger index = 0; index < 4; ++index) {
    [points addObject:@{
      @"x" : @(location.coordinates[index * 2]),
      @"y" : @(location.coordinates[index * 2 + 1]),
    }];
  }
  return @{ @"points" : points };
}

NSDictionary* ResultMap(const VisionResult& result) {
  NSMutableArray* barcodes = [NSMutableArray array];
  for (const auto& barcode : result.barcodes) {
    NSData* bytes = [NSData dataWithBytes:barcode.raw_bytes.data()
                                    length:barcode.raw_bytes.size()];
    [barcodes addObject:@{
      @"format" : [NSString stringWithUTF8String:barcode.format.c_str()],
      @"text" : [NSString stringWithUTF8String:barcode.text.c_str()],
      @"rawBytes" : bytes,
      @"confidence" : @(barcode.confidence),
      @"location" : QuadrilateralMap(barcode.location),
    }];
  }
  NSMutableArray* mrzResults = [NSMutableArray array];
  for (const auto& mrz : result.mrz_results) {
    NSMutableDictionary* fields = [NSMutableDictionary dictionary];
    for (const auto& field : mrz.fields) {
      fields[[NSString stringWithUTF8String:field.first.c_str()]] =
          [NSString stringWithUTF8String:field.second.c_str()];
    }
    NSMutableDictionary* value = [NSMutableDictionary dictionary];
    value[@"rawText"] = [NSString stringWithUTF8String:mrz.raw_text.c_str()];
    value[@"documentType"] =
        [NSString stringWithUTF8String:mrz.document_type.c_str()];
    value[@"fields"] = fields;
    if (mrz.has_location) {
      value[@"location"] = QuadrilateralMap(mrz.location);
      value[@"confidence"] = @(mrz.confidence);
    }
    [mrzResults addObject:value];
  }
  NSMutableArray* detections = [NSMutableArray array];
  for (const auto& detection : result.document_detections) {
    [detections addObject:@{
      @"confidence" : @(detection.confidence),
      @"location" : QuadrilateralMap(detection.location),
    }];
  }
  return @{
    @"barcodes" : barcodes,
    @"mrzResults" : mrzResults,
    @"documentDetections" : detections,
  };
}

FlutterError* FlutterErrorFor(const VisionError& error) {
  return [FlutterError errorWithCode:[NSString stringWithFormat:@"%d", error.code]
                             message:[NSString stringWithUTF8String:error.what()]
                             details:nil];
}

}  // namespace

@implementation FlutterCaptureVisionPlugin {
  VisionRouter* _router;
  dispatch_queue_t _workerQueue;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:kChannelName binaryMessenger:[registrar messenger]];
  FlutterCaptureVisionPlugin* instance = [[FlutterCaptureVisionPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    // DCV owns mutable router/template state. One serial worker provides both
    // thread affinity and a non-blocking MethodChannel boundary for every
    // operation, not only image capture.
    _workerQueue = dispatch_queue_create("com.dynamsoft.flutter_capture_vision", DISPATCH_QUEUE_SERIAL);
    _router = nullptr;
  }
  return self;
}

- (void)dealloc {
  // The queue is serial, so this waits for an already-running capture before
  // releasing its router rather than racing a native SDK call.
  dispatch_sync(_workerQueue, ^{
    delete _router;
    _router = nullptr;
  });
}

- (void)complete:(FlutterResult)result value:(id)value {
  dispatch_async(dispatch_get_main_queue(), ^{
    result(value);
  });
}

- (void)complete:(FlutterResult)result error:(FlutterError*)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    result(error);
  });
}

- (void)runAsync:(FlutterResult)result operation:(id (^)(void))operation {
  dispatch_async(_workerQueue, ^{
    try {
      id value = operation();
      [self complete:result value:value];
    } catch (const VisionError& error) {
      [self complete:result error:FlutterErrorFor(error)];
    } catch (const std::exception& error) {
      [self complete:result error:[FlutterError errorWithCode:@"native_error"
                                                      message:[NSString stringWithUTF8String:error.what()]
                                                      details:nil]];
    }
  });
}

- (VisionRouter*)router {
  if (_router == nullptr) {
    throw VisionError(-1, "Call initialize() before using Capture Vision.");
  }
  return _router;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  const NSString* method = [call.method copy];
  NSDictionary* arguments = [call.arguments isKindOfClass:[NSDictionary class]]
      ? [call.arguments copy] : @{};
  [self runAsync:result operation:^id {
    if ([method isEqualToString:@"initialize"]) {
      if (_router == nullptr) _router = new VisionRouter();
      _router->Initialize(std::string([RequiredString(arguments, @"licenseKey") UTF8String]));
      return nil;
    }
    if ([method isEqualToString:@"initSettings"]) {
      [self router]->InitSettings(std::string([RequiredString(arguments, @"settingsJson") UTF8String]));
      return nil;
    }
    if ([method isEqualToString:@"resetSettings"]) {
      [self router]->ResetSettings();
      return nil;
    }
    if ([method isEqualToString:@"captureFile"]) {
      const VisionResult nativeResult = [self router]->CaptureFile(
          std::string([RequiredString(arguments, @"path") UTF8String]),
          TemplatesForRequest(arguments));
      return ResultMap(nativeResult);
    }
    if ([method isEqualToString:@"captureBuffer"]) {
      NSDictionary* buffer = RequiredMap(arguments, @"buffer");
      id rawBytes = buffer[@"bytes"];
      if (![rawBytes isKindOfClass:[FlutterStandardTypedData class]]) {
        throw VisionError(-1, "Buffer bytes must be Uint8List.");
      }
      // Retain an owned copy before the asynchronous native capture begins.
      NSData* bytes = [((FlutterStandardTypedData*)rawBytes).data copy];
      const VisionResult nativeResult = [self router]->CaptureBuffer(
          static_cast<const uint8_t*>(bytes.bytes), bytes.length,
          (int)RequiredInteger(buffer, @"width"),
          (int)RequiredInteger(buffer, @"height"),
          (int)RequiredInteger(buffer, @"stride"),
          std::string([RequiredString(buffer, @"pixelFormat") UTF8String]),
          (int)RequiredInteger(buffer, @"rotation"), TemplatesForRequest(arguments));
      return ResultMap(nativeResult);
    }
    if ([method isEqualToString:@"dispose"]) {
      delete _router;
      _router = nullptr;
      return nil;
    }
    return FlutterMethodNotImplemented;
  }];
}

@end
