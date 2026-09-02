#include "include/flutter_capture_vision_linux/flutter_capture_vision_plugin.h"
#include "include/vision_router.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>
#include <condition_variable>
#include <exception>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

using flutter_capture_vision::VisionError;
using flutter_capture_vision::VisionQuadrilateral;
using flutter_capture_vision::VisionResult;
using flutter_capture_vision::VisionRouter;

namespace {
struct PluginState;
}

#define FLUTTER_CAPTURE_VISION_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_capture_vision_plugin_get_type(), \
                              FlutterCaptureVisionPlugin))

struct _FlutterCaptureVisionPlugin {
  GObject parent_instance;
  PluginState* state;
};

G_DEFINE_TYPE(FlutterCaptureVisionPlugin, flutter_capture_vision_plugin,
              g_object_get_type())

namespace {

FlValue* Required(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    throw VisionError(-1, "Method arguments must be a map.");
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) {
    throw VisionError(-1, std::string("Missing required argument: ") + key);
  }
  return value;
}

const char* RequiredString(FlValue* map, const char* key) {
  FlValue* value = Required(map, key);
  if (fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    throw VisionError(-1, std::string("Argument '") + key + "' must be a string.");
  }
  return fl_value_get_string(value);
}

int RequiredInt(FlValue* map, const char* key) {
  FlValue* value = Required(map, key);
  if (fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    throw VisionError(-1, std::string("Argument '") + key + "' must be an integer.");
  }
  return static_cast<int>(fl_value_get_int(value));
}

FlValue* RequiredMap(FlValue* map, const char* key) {
  FlValue* value = Required(map, key);
  if (fl_value_get_type(value) != FL_VALUE_TYPE_MAP) {
    throw VisionError(-1, std::string("Argument '") + key + "' must be a map.");
  }
  return value;
}

std::vector<std::string> TemplatesForRequest(FlValue* arguments) {
  FlValue* request = RequiredMap(arguments, "request");
  const std::string type = RequiredString(request, "type");
  if (type == "template") return {RequiredString(request, "templateName")};
  if (type != "tasks") {
    throw VisionError(-1, "Request type must be 'tasks' or 'template'.");
  }
  FlValue* tasks = Required(request, "tasks");
  if (fl_value_get_type(tasks) != FL_VALUE_TYPE_LIST || fl_value_get_length(tasks) == 0) {
    throw VisionError(-1, "A task request requires at least one task.");
  }
  std::vector<std::string> templates;
  for (size_t index = 0; index < fl_value_get_length(tasks); ++index) {
    FlValue* task = fl_value_get_list_value(tasks, index);
    if (fl_value_get_type(task) != FL_VALUE_TYPE_STRING) {
      throw VisionError(-1, "Every task must be a string.");
    }
    const std::string value = fl_value_get_string(task);
    if (value == "barcode") templates.emplace_back("ReadBarcodes_Default");
    else if (value == "mrz") templates.emplace_back("ReadPassportAndId");
    else if (value == "documentDetection") templates.emplace_back("DetectDocumentBoundaries_Default");
    else throw VisionError(-1, "Unknown Capture Vision task: " + value);
  }
  return templates;
}

FlValue* QuadrilateralMap(const VisionQuadrilateral& location) {
  FlValue* map = fl_value_new_map();
  FlValue* points = fl_value_new_list();
  for (size_t index = 0; index < 4; ++index) {
    FlValue* point = fl_value_new_map();
    fl_value_set_string_take(point, "x", fl_value_new_float(
        location.coordinates[index * 2]));
    fl_value_set_string_take(point, "y", fl_value_new_float(
        location.coordinates[index * 2 + 1]));
    fl_value_append_take(points, point);
  }
  fl_value_set_string_take(map, "points", points);
  return map;
}

FlValue* ResultMap(const VisionResult& result) {
  FlValue* envelope = fl_value_new_map();
  FlValue* barcodes = fl_value_new_list();
  for (const auto& barcode : result.barcodes) {
    FlValue* value = fl_value_new_map();
    fl_value_set_string_take(value, "format", fl_value_new_string(barcode.format.c_str()));
    fl_value_set_string_take(value, "text", fl_value_new_string(barcode.text.c_str()));
    fl_value_set_string_take(value, "rawBytes", fl_value_new_uint8_list(
        barcode.raw_bytes.data(), barcode.raw_bytes.size()));
    fl_value_set_string_take(value, "confidence", fl_value_new_float(barcode.confidence));
    fl_value_set_string_take(value, "location", QuadrilateralMap(barcode.location));
    fl_value_append_take(barcodes, value);
  }
  FlValue* mrz_results = fl_value_new_list();
  for (const auto& mrz : result.mrz_results) {
    FlValue* value = fl_value_new_map();
    FlValue* fields = fl_value_new_map();
    for (const auto& field : mrz.fields) {
      fl_value_set_string_take(fields, field.first.c_str(),
                               fl_value_new_string(field.second.c_str()));
    }
    fl_value_set_string_take(value, "rawText", fl_value_new_string(mrz.raw_text.c_str()));
    fl_value_set_string_take(value, "documentType", fl_value_new_string(mrz.document_type.c_str()));
    fl_value_set_string_take(value, "fields", fields);
    if (mrz.has_location) {
      fl_value_set_string_take(value, "location", QuadrilateralMap(mrz.location));
      fl_value_set_string_take(value, "confidence", fl_value_new_float(mrz.confidence));
    }
    fl_value_append_take(mrz_results, value);
  }
  FlValue* document_detections = fl_value_new_list();
  for (const auto& detection : result.document_detections) {
    FlValue* value = fl_value_new_map();
    fl_value_set_string_take(value, "confidence", fl_value_new_float(detection.confidence));
    fl_value_set_string_take(value, "location", QuadrilateralMap(detection.location));
    fl_value_append_take(document_detections, value);
  }
  fl_value_set_string_take(envelope, "barcodes", barcodes);
  fl_value_set_string_take(envelope, "mrzResults", mrz_results);
  fl_value_set_string_take(envelope, "documentDetections", document_detections);
  return envelope;
}

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

struct MainThreadResponse {
  FlMethodCall* call;
  std::function<FlMethodResponse*()> create_response;
};

gboolean DeliverMainThreadResponse(gpointer raw_response) {
  std::unique_ptr<MainThreadResponse> pending(
      static_cast<MainThreadResponse*>(raw_response));
  FlMethodResponse* response = pending->create_response();
  fl_method_call_respond(pending->call, response, nullptr);
  g_object_unref(response);
  g_object_unref(pending->call);
  return G_SOURCE_REMOVE;
}

void RespondOnMainThread(FlMethodCall* call,
                         std::function<FlMethodResponse*()> create_response) {
  auto* pending = new MainThreadResponse{
      FL_METHOD_CALL(g_object_ref(call)), std::move(create_response)};
  g_main_context_invoke(nullptr, DeliverMainThreadResponse, pending);
}

void RespondSuccess(FlMethodCall* call) {
  RespondOnMainThread(call, [] {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  });
}

void RespondResult(FlMethodCall* call, std::shared_ptr<VisionResult> result) {
  RespondOnMainThread(call, [result] {
    g_autoptr(FlValue) output = ResultMap(*result);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(output));
  });
}

void RespondError(FlMethodCall* call, std::string code, std::string message) {
  RespondOnMainThread(call, [code = std::move(code), message = std::move(message)] {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        code.c_str(), message.c_str(), nullptr));
  });
}

void RespondNotImplemented(FlMethodCall* call) {
  RespondOnMainThread(call, [] {
    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  });
}

enum class InvocationType {
  kInitialize,
  kInitSettings,
  kResetSettings,
  kCaptureFile,
  kCaptureBuffer,
  kDispose,
  kNotImplemented,
};

struct Invocation {
  InvocationType type;
  std::string string_value;
  std::vector<std::string> templates;
  std::vector<uint8_t> bytes;
  int width = 0;
  int height = 0;
  int stride = 0;
  int rotation = 0;
  std::string pixel_format;
};

Invocation ParseInvocation(const char* method, FlValue* arguments) {
  if (strcmp(method, "resetSettings") == 0) return {InvocationType::kResetSettings};
  if (strcmp(method, "dispose") == 0) return {InvocationType::kDispose};
  if (strcmp(method, "initialize") == 0) {
    return {InvocationType::kInitialize, RequiredString(arguments, "licenseKey")};
  }
  if (strcmp(method, "initSettings") == 0) {
    return {InvocationType::kInitSettings, RequiredString(arguments, "settingsJson")};
  }
  if (strcmp(method, "captureFile") == 0) {
    Invocation invocation{InvocationType::kCaptureFile};
    invocation.string_value = RequiredString(arguments, "path");
    invocation.templates = TemplatesForRequest(arguments);
    return invocation;
  }
  if (strcmp(method, "captureBuffer") == 0) {
    FlValue* buffer = RequiredMap(arguments, "buffer");
    FlValue* raw_bytes = Required(buffer, "bytes");
    if (fl_value_get_type(raw_bytes) != FL_VALUE_TYPE_UINT8_LIST) {
      throw VisionError(-1, "Buffer bytes must be Uint8List.");
    }
    Invocation invocation{InvocationType::kCaptureBuffer};
    const auto* bytes = fl_value_get_uint8_list(raw_bytes);
    invocation.bytes.assign(bytes, bytes + fl_value_get_length(raw_bytes));
    invocation.width = RequiredInt(buffer, "width");
    invocation.height = RequiredInt(buffer, "height");
    invocation.stride = RequiredInt(buffer, "stride");
    invocation.rotation = RequiredInt(buffer, "rotation");
    invocation.pixel_format = RequiredString(buffer, "pixelFormat");
    invocation.templates = TemplatesForRequest(arguments);
    return invocation;
  }
  return {InvocationType::kNotImplemented};
}

void RunInvocation(PluginState* state, FlMethodCall* call, Invocation invocation) {
  try {
    switch (invocation.type) {
      case InvocationType::kInitialize:
        state->router.Initialize(invocation.string_value);
        RespondSuccess(call);
        return;
      case InvocationType::kInitSettings:
        state->router.InitSettings(invocation.string_value);
        RespondSuccess(call);
        return;
      case InvocationType::kResetSettings:
        state->router.ResetSettings();
        RespondSuccess(call);
        return;
      case InvocationType::kCaptureFile:
        RespondResult(call, std::make_shared<VisionResult>(
            state->router.CaptureFile(invocation.string_value, invocation.templates)));
        return;
      case InvocationType::kCaptureBuffer:
        RespondResult(call, std::make_shared<VisionResult>(
            state->router.CaptureBuffer(
                invocation.bytes.data(), invocation.bytes.size(), invocation.width,
                invocation.height, invocation.stride, invocation.pixel_format,
                invocation.rotation, invocation.templates)));
        return;
      case InvocationType::kDispose:
        state->router.Dispose();
        RespondSuccess(call);
        return;
      case InvocationType::kNotImplemented:
        RespondNotImplemented(call);
        return;
    }
  } catch (const VisionError& error) {
    RespondError(call, std::to_string(error.code), error.what());
  } catch (const std::exception& error) {
    RespondError(call, "native_error", error.what());
  }
}

void HandleMethodCall(FlutterCaptureVisionPlugin* self, FlMethodCall* call) {
  Invocation invocation{InvocationType::kNotImplemented};
  try {
    invocation = ParseInvocation(fl_method_call_get_name(call),
                                 fl_method_call_get_args(call));
  } catch (const VisionError& error) {
    RespondError(call, std::to_string(error.code), error.what());
    return;
  } catch (const std::exception& error) {
    RespondError(call, "native_error", error.what());
    return;
  }
  PluginState* const state = self->state;
  state->worker.Post([state, call = FL_METHOD_CALL(g_object_ref(call)),
                      invocation = std::move(invocation)]() mutable {
    RunInvocation(state, call, std::move(invocation));
    g_object_unref(call);
  });
}

void MethodCallCallback(FlMethodChannel*, FlMethodCall* method_call,
                        gpointer user_data) {
  HandleMethodCall(FLUTTER_CAPTURE_VISION_PLUGIN(user_data), method_call);
}

}  // namespace

static void flutter_capture_vision_plugin_dispose(GObject* object) {
  FlutterCaptureVisionPlugin* self = FLUTTER_CAPTURE_VISION_PLUGIN(object);
  delete self->state;
  self->state = nullptr;
  G_OBJECT_CLASS(flutter_capture_vision_plugin_parent_class)->dispose(object);
}

static void flutter_capture_vision_plugin_class_init(FlutterCaptureVisionPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_capture_vision_plugin_dispose;
}

static void flutter_capture_vision_plugin_init(FlutterCaptureVisionPlugin* self) {
  self->state = new PluginState();
}

void flutter_capture_vision_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterCaptureVisionPlugin* plugin = FLUTTER_CAPTURE_VISION_PLUGIN(
      g_object_new(flutter_capture_vision_plugin_get_type(), nullptr));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "flutter_capture_vision",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, MethodCallCallback,
      g_object_ref(plugin), g_object_unref);
  g_object_unref(plugin);
}
