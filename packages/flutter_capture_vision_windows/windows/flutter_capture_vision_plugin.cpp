#include "include/flutter_capture_vision_windows/flutter_capture_vision_plugin.h"
#include "include/vision_router.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter_capture_vision::VisionDocumentDetection;
using flutter_capture_vision::VisionError;
using flutter_capture_vision::VisionMrz;
using flutter_capture_vision::VisionQuadrilateral;
using flutter_capture_vision::VisionResult;
using flutter_capture_vision::VisionRouter;

const EncodableValue& Key(const char* key) {
  static const EncodableValue kLicenseKey("licenseKey");
  static const EncodableValue kSettingsJson("settingsJson");
  static const EncodableValue kPath("path");
  static const EncodableValue kRequest("request");
  static const EncodableValue kBuffer("buffer");
  static const EncodableValue kType("type");
  static const EncodableValue kTasks("tasks");
  static const EncodableValue kTemplateName("templateName");
  static const EncodableValue kBytes("bytes");
  static const EncodableValue kWidth("width");
  static const EncodableValue kHeight("height");
  static const EncodableValue kStride("stride");
  static const EncodableValue kPixelFormat("pixelFormat");
  const std::string requested(key);
  if (requested == "licenseKey") return kLicenseKey;
  if (requested == "settingsJson") return kSettingsJson;
  if (requested == "path") return kPath;
  if (requested == "request") return kRequest;
  if (requested == "buffer") return kBuffer;
  if (requested == "type") return kType;
  if (requested == "tasks") return kTasks;
  if (requested == "templateName") return kTemplateName;
  if (requested == "bytes") return kBytes;
  if (requested == "width") return kWidth;
  if (requested == "height") return kHeight;
  if (requested == "stride") return kStride;
  return kPixelFormat;
}

const EncodableValue& Required(const EncodableMap& map, const char* key) {
  const auto item = map.find(Key(key));
  if (item == map.end()) {
    throw VisionError(-1, std::string("Missing required argument: ") + key);
  }
  return item->second;
}

std::string RequiredString(const EncodableMap& map, const char* key) {
  const EncodableValue& value = Required(map, key);
  if (const auto* text = std::get_if<std::string>(&value)) return *text;
  throw VisionError(-1, std::string("Argument '") + key + "' must be a string.");
}

int RequiredInt(const EncodableMap& map, const char* key) {
  const EncodableValue& value = Required(map, key);
  if (const auto* integer = std::get_if<int>(&value)) return *integer;
  if (const auto* integer64 = std::get_if<int64_t>(&value)) return static_cast<int>(*integer64);
  throw VisionError(-1, std::string("Argument '") + key + "' must be an integer.");
}

EncodableMap RequiredMap(const EncodableMap& map, const char* key) {
  const EncodableValue& value = Required(map, key);
  if (const auto* inner = std::get_if<EncodableMap>(&value)) return *inner;
  throw VisionError(-1, std::string("Argument '") + key + "' must be a map.");
}

std::vector<std::string> TemplatesForRequest(const EncodableMap& arguments) {
  const EncodableMap request = RequiredMap(arguments, "request");
  const std::string type = RequiredString(request, "type");
  if (type == "template") {
    return {RequiredString(request, "templateName")};
  }
  if (type != "tasks") {
    throw VisionError(-1, "Request type must be 'tasks' or 'template'.");
  }
  const EncodableValue& raw_tasks = Required(request, "tasks");
  const auto* tasks = std::get_if<EncodableList>(&raw_tasks);
  if (tasks == nullptr || tasks->empty()) {
    throw VisionError(-1, "A task request requires at least one task.");
  }
  std::vector<std::string> templates;
  for (const EncodableValue& task_value : *tasks) {
    const auto* task = std::get_if<std::string>(&task_value);
    if (task == nullptr) throw VisionError(-1, "Every task must be a string.");
    if (*task == "barcode") templates.push_back("ReadBarcodes_Default");
    else if (*task == "mrz") templates.push_back("ReadPassportAndId");
    else if (*task == "documentDetection") templates.push_back("DetectDocumentBoundaries_Default");
    else throw VisionError(-1, "Unknown Capture Vision task: " + *task);
  }
  return templates;
}

EncodableMap QuadrilateralMap(const VisionQuadrilateral& location) {
  EncodableList points;
  for (size_t index = 0; index < 4; ++index) {
    EncodableMap point;
    point[EncodableValue("x")] = EncodableValue(location.coordinates[index * 2]);
    point[EncodableValue("y")] = EncodableValue(location.coordinates[index * 2 + 1]);
    points.emplace_back(point);
  }
  EncodableMap result;
  result[EncodableValue("points")] = EncodableValue(points);
  return result;
}

EncodableMap ResultMap(const VisionResult& result) {
  EncodableList barcodes;
  for (const auto& barcode : result.barcodes) {
    EncodableMap value;
    value[EncodableValue("format")] = EncodableValue(barcode.format);
    value[EncodableValue("text")] = EncodableValue(barcode.text);
    value[EncodableValue("rawBytes")] = EncodableValue(barcode.raw_bytes);
    value[EncodableValue("confidence")] = EncodableValue(barcode.confidence);
    value[EncodableValue("location")] = EncodableValue(QuadrilateralMap(barcode.location));
    barcodes.emplace_back(value);
  }
  EncodableList mrz_results;
  for (const VisionMrz& mrz : result.mrz_results) {
    EncodableMap fields;
    for (const auto& field : mrz.fields) fields[EncodableValue(field.first)] = EncodableValue(field.second);
    EncodableMap value;
    value[EncodableValue("rawText")] = EncodableValue(mrz.raw_text);
    value[EncodableValue("documentType")] = EncodableValue(mrz.document_type);
    value[EncodableValue("fields")] = EncodableValue(fields);
    if (mrz.has_location) {
      value[EncodableValue("location")] = EncodableValue(QuadrilateralMap(mrz.location));
      value[EncodableValue("confidence")] = EncodableValue(mrz.confidence);
    }
    mrz_results.emplace_back(value);
  }
  EncodableList detections;
  for (const VisionDocumentDetection& detection : result.document_detections) {
    EncodableMap value;
    value[EncodableValue("confidence")] = EncodableValue(detection.confidence);
    value[EncodableValue("location")] = EncodableValue(QuadrilateralMap(detection.location));
    detections.emplace_back(value);
  }
  EncodableMap envelope;
  envelope[EncodableValue("barcodes")] = EncodableValue(barcodes);
  envelope[EncodableValue("mrzResults")] = EncodableValue(mrz_results);
  envelope[EncodableValue("documentDetections")] = EncodableValue(detections);
  return envelope;
}

/// Owns one background thread for the complete DCV lifecycle. Captures and
/// template mutations must retain call order: a settings reset that races a
/// camera capture would otherwise make its selected template unpredictable.
class SerialExecutor {
 public:
  SerialExecutor() : thread_([this] { Run(); }) {}

  ~SerialExecutor() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopped_ = true;
    }
    condition_.notify_one();
    if (thread_.joinable()) thread_.join();
  }

  void Post(std::function<void()> task) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      tasks_.push(std::move(task));
    }
    condition_.notify_one();
  }

 private:
  void Run() {
    while (true) {
      std::function<void()> task;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock, [this] { return stopped_ || !tasks_.empty(); });
        if (stopped_ && tasks_.empty()) return;
        task = std::move(tasks_.front());
        tasks_.pop();
      }
      task();
    }
  }

  std::mutex mutex_;
  std::condition_variable condition_;
  std::queue<std::function<void()>> tasks_;
  bool stopped_ = false;
  std::thread thread_;
};

struct PluginState {
  VisionRouter router;
  SerialExecutor worker;
};

class FlutterCaptureVisionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar->messenger(), "flutter_capture_vision",
        &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<FlutterCaptureVisionPlugin>();
    channel->SetMethodCallHandler([pointer = plugin.get()](const auto& call, auto result) {
      pointer->HandleMethodCall(call, std::move(result));
    });
    registrar->AddPlugin(std::move(plugin));
  }

  FlutterCaptureVisionPlugin() : state_(std::make_unique<PluginState>()) {}

 private:
  void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const EncodableMap arguments = [&call] {
      const auto* values = std::get_if<EncodableMap>(call.arguments());
      return values == nullptr ? EncodableMap() : *values;
    }();
    const std::string method = call.method_name();
    auto pending = std::shared_ptr<flutter::MethodResult<EncodableValue>>(std::move(result));
    PluginState* const state = state_.get();
    state->worker.Post([state, method, arguments, pending] {
      try {
        if (method == "resetSettings") {
          state->router.ResetSettings();
          pending->Success();
        } else if (method == "dispose") {
          state->router.Dispose();
          pending->Success();
        } else if (method == "initialize") {
          state->router.Initialize(RequiredString(arguments, "licenseKey"));
          pending->Success();
        } else if (method == "initSettings") {
          state->router.InitSettings(RequiredString(arguments, "settingsJson"));
          pending->Success();
        } else if (method == "captureFile") {
          pending->Success(EncodableValue(ResultMap(state->router.CaptureFile(
              RequiredString(arguments, "path"), TemplatesForRequest(arguments)))));
        } else if (method == "captureBuffer") {
          const EncodableMap buffer = RequiredMap(arguments, "buffer");
          const EncodableValue& bytes_value = Required(buffer, "bytes");
          const auto* bytes = std::get_if<std::vector<uint8_t>>(&bytes_value);
          if (bytes == nullptr) throw VisionError(-1, "Buffer bytes must be Uint8List.");
          // EncodableMap was copied before queuing; this additional owned vector
          // prevents any capture from retaining MethodChannel-owned memory.
          const std::vector<uint8_t> copied_bytes = *bytes;
          pending->Success(EncodableValue(ResultMap(state->router.CaptureBuffer(
              copied_bytes.data(), copied_bytes.size(), RequiredInt(buffer, "width"),
              RequiredInt(buffer, "height"), RequiredInt(buffer, "stride"),
              RequiredString(buffer, "pixelFormat"), RequiredInt(buffer, "rotation"),
              TemplatesForRequest(arguments)))));
        } else {
          pending->NotImplemented();
        }
      } catch (const VisionError& error) {
        pending->Error(std::to_string(error.code), error.what());
      } catch (const std::exception& error) {
        pending->Error("native_error", error.what());
      }
    });
  }

  std::unique_ptr<PluginState> state_;
};

}  // namespace

void FlutterCaptureVisionPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterCaptureVisionPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
