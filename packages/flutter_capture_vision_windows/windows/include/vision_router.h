#ifndef FLUTTER_CAPTURE_VISION_VISION_ROUTER_H_
#define FLUTTER_CAPTURE_VISION_VISION_ROUTER_H_

#include "DynamsoftBarcodeReader.h"
#include "DynamsoftCaptureVisionRouter.h"
#include "DynamsoftCodeParser.h"
#include "DynamsoftDocumentNormalizer.h"
#include "DynamsoftLabelRecognizer.h"
#include "DynamsoftLicense.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <mutex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace flutter_capture_vision {

using dynamsoft::basic_structures::CImageData;
using dynamsoft::basic_structures::CQuadrilateral;
using ::ImagePixelFormat;
using dynamsoft::cvr::CCaptureVisionRouter;

struct VisionQuadrilateral {
  std::array<double, 8> coordinates{};
};

struct VisionBarcode {
  std::string format;
  std::string text;
  std::vector<uint8_t> raw_bytes;
  VisionQuadrilateral location;
  double confidence = 0;
};

struct VisionMrz {
  std::string raw_text;
  std::string document_type;
  std::vector<std::pair<std::string, std::string>> fields;
  VisionQuadrilateral location{};
  double confidence = 0;
  bool has_location = false;
};

struct VisionDocumentDetection {
  VisionQuadrilateral location;
  double confidence = 0;
};

struct VisionResult {
  std::vector<VisionBarcode> barcodes;
  std::vector<VisionMrz> mrz_results;
  std::vector<VisionDocumentDetection> document_detections;
};

/// Raised when an SDK operation fails. Platform shims turn this into a
/// Flutter PlatformException, preserving the native error code and message.
class VisionError : public std::runtime_error {
 public:
  VisionError(int code, const std::string& message)
      : std::runtime_error(message), code(code) {}

  int code;
};

/// Thread-safe, synchronous DCV router. Flutter serializes public calls, but
/// the mutex also protects embedders that may dispatch channel calls on more
/// than one native thread.
class VisionRouter {
 public:
  VisionRouter() : router_(new CCaptureVisionRouter()) {}

  ~VisionRouter() { delete router_; }

  VisionRouter(const VisionRouter&) = delete;
  VisionRouter& operator=(const VisionRouter&) = delete;

  void Initialize(const std::string& license_key) {
    std::lock_guard<std::mutex> lock(mutex_);
    char error[512] = {0};
    const int code = dynamsoft::license::CLicenseManager::InitLicense(
        license_key.c_str(), error, sizeof(error));
    if (code != 0) {
      throw VisionError(code, ErrorMessage(error, "Unable to initialize the DCV license."));
    }
    initialized_ = true;
  }

  void InitSettings(const std::string& settings_json) {
    std::lock_guard<std::mutex> lock(mutex_);
    EnsureInitialized();
    char error[512] = {0};
    const int code = router_->InitSettings(settings_json.c_str(), error, sizeof(error));
    if (code != 0) {
      throw VisionError(code, ErrorMessage(error, "DCV rejected the settings JSON."));
    }
  }

  void ResetSettings() {
    std::lock_guard<std::mutex> lock(mutex_);
    EnsureInitialized();
    const int code = router_->ResetSettings();
    if (code != 0) {
      throw VisionError(code, "DCV could not restore its factory settings.");
    }
  }

  VisionResult CaptureFile(const std::string& path,
                           const std::vector<std::string>& template_names) {
    std::lock_guard<std::mutex> lock(mutex_);
    EnsureInitialized();
    return CaptureEach(template_names, [&](const std::string& template_name) {
      return router_->Capture(path.c_str(), template_name.c_str());
    });
  }

  VisionResult CaptureBuffer(const uint8_t* bytes, size_t length, int width,
                             int height, int stride,
                             const std::string& pixel_format, int rotation,
                             const std::vector<std::string>& template_names) {
    std::lock_guard<std::mutex> lock(mutex_);
    EnsureInitialized();
    if (bytes == nullptr || length == 0 || width <= 0 || height <= 0 || stride <= 0) {
      throw VisionError(-1, "The image buffer is empty or has invalid geometry.");
    }
    const CImageData image(length, bytes, width, height, stride,
                           PixelFormatFromName(pixel_format), rotation);
    return CaptureEach(template_names, [&](const std::string& template_name) {
      return router_->Capture(&image, template_name.c_str());
    });
  }

  void Dispose() {
    std::lock_guard<std::mutex> lock(mutex_);
    initialized_ = false;
  }

 private:
  template <typename Capture>
  VisionResult CaptureEach(const std::vector<std::string>& template_names,
                           Capture capture) {
    if (template_names.empty()) {
      throw VisionError(-1, "At least one DCV template name is required.");
    }
    VisionResult result;
    for (const std::string& template_name : template_names) {
      dynamsoft::cvr::CCapturedResult* captured = capture(template_name);
      if (captured == nullptr) {
        throw VisionError(-1, "DCV returned no capture result.");
      }
      const int code = captured->GetErrorCode();
      if (code != 0) {
        const std::string message = ErrorMessage(
            captured->GetErrorString(), "DCV capture failed for template '" + template_name + "'.");
        captured->Release();
        throw VisionError(code, message);
      }
      AppendResult(captured, &result);
      captured->Release();
    }
    return result;
  }

  void AppendResult(dynamsoft::cvr::CCapturedResult* captured,
                    VisionResult* destination) {
    AppendBarcodes(captured, destination);
    AppendMrz(captured, destination);
    AppendDocumentDetections(captured, destination);
  }

  void AppendBarcodes(dynamsoft::cvr::CCapturedResult* captured,
                      VisionResult* destination) {
    dynamsoft::dbr::CDecodedBarcodesResult* barcodes =
        captured->GetDecodedBarcodesResult();
    if (barcodes == nullptr) return;
    for (int index = 0; index < barcodes->GetItemsCount(); ++index) {
      const dynamsoft::dbr::CBarcodeResultItem* item = barcodes->GetItem(index);
      if (item == nullptr) continue;
      VisionBarcode barcode;
      barcode.format = SafeString(item->GetFormatString());
      barcode.text = SafeString(item->GetText());
      barcode.location = ToQuadrilateral(item->GetLocation());
      barcode.confidence = item->GetConfidence();
      const unsigned char* raw_bytes = item->GetBytes();
      const int raw_bytes_length = item->GetBytesLength();
      if (raw_bytes != nullptr && raw_bytes_length > 0) {
        barcode.raw_bytes.assign(raw_bytes, raw_bytes + raw_bytes_length);
      }
      destination->barcodes.push_back(std::move(barcode));
    }
    barcodes->Release();
  }

  void AppendMrz(dynamsoft::cvr::CCapturedResult* captured,
                 VisionResult* destination) {
    // The parsed item itself carries no geometry. The MRZ zone is the union
    // of the recognized text-line quads; when the parser produced nothing
    // (low resolution or a damaged zone) the raw lines become the result.
    VisionQuadrilateral zone{};
    double lowest_confidence = 0;
    bool has_zone = false;
    std::vector<std::string> raw_lines;
    if (dynamsoft::dlr::CRecognizedTextLinesResult* text_lines =
            captured->GetRecognizedTextLinesResult()) {
      const int count = text_lines->GetItemsCount();
      int min_x = 0, min_y = 0, max_x = 0, max_y = 0;
      bool first_point = true;
      for (int index = 0; index < count; ++index) {
        const dynamsoft::dlr::CTextLineResultItem* item = text_lines->GetItem(index);
        if (item == nullptr) continue;
        const std::string text = SafeString(item->GetText());
        if (!text.empty()) raw_lines.push_back(text);
        const CQuadrilateral location = item->GetLocation();
        for (int point_index = 0; point_index < 4; ++point_index) {
          const int x = location.points[point_index][0];
          const int y = location.points[point_index][1];
          if (first_point) {
            min_x = max_x = x;
            min_y = max_y = y;
            first_point = false;
          } else {
            // Parentheses defeat the Windows min/max macros (defined by
            // windows.h, pulled in transitively) which would otherwise
            // expand std::min/std::max into a syntax error (C2589/C2059).
            min_x = (std::min)(min_x, x);
            min_y = (std::min)(min_y, y);
            max_x = (std::max)(max_x, x);
            max_y = (std::max)(max_y, y);
          }
        }
        const int confidence = item->GetConfidence();
        if (first_point || index == 0 || confidence < lowest_confidence) {
          lowest_confidence = confidence;
        }
      }
      text_lines->Release();
      if (!first_point) {
        zone.coordinates = {double(min_x), double(min_y), double(max_x),
                            double(min_y), double(max_x), double(max_y),
                            double(min_x), double(max_y)};
        has_zone = true;
      }
    }
    dynamsoft::dcp::CParsedResult* parsed = captured->GetParsedResult();
    if (parsed != nullptr) {
    for (int index = 0; index < parsed->GetItemsCount(); ++index) {
      const dynamsoft::dcp::CParsedResultItem* item = parsed->GetItem(index);
      if (item == nullptr) continue;
      VisionMrz mrz;
      mrz.document_type = SafeString(item->GetCodeType());
      std::vector<std::string> lines;
      for (int field_index = 0; field_index < item->GetFieldCount(); ++field_index) {
        const std::string name = SafeString(item->GetFieldName(field_index));
        if (name.empty()) continue;
        const std::string value = SafeString(item->GetFieldValue(name.c_str()));
        if (!value.empty()) {
          mrz.fields.emplace_back(name, value);
          if (name == "line1" || name == "line2" || name == "line3") {
            lines.push_back(value);
          }
        }
      }
      for (size_t line_index = 0; line_index < lines.size(); ++line_index) {
        if (line_index != 0) mrz.raw_text.push_back('\n');
        mrz.raw_text += lines[line_index];
      }
      if (has_zone) {
        mrz.location = zone;
        mrz.confidence = lowest_confidence;
        mrz.has_location = true;
      }
      destination->mrz_results.push_back(std::move(mrz));
    }
      parsed->Release();
    }
    if (destination->mrz_results.empty() && !raw_lines.empty() && has_zone) {
      VisionMrz mrz;
      for (size_t line_index = 0; line_index < raw_lines.size(); ++line_index) {
        if (line_index != 0) mrz.raw_text.push_back('\n');
        mrz.raw_text += raw_lines[line_index];
      }
      mrz.location = zone;
      mrz.confidence = lowest_confidence;
      mrz.has_location = true;
      destination->mrz_results.push_back(std::move(mrz));
    }
  }

  void AppendDocumentDetections(dynamsoft::cvr::CCapturedResult* captured,
                                VisionResult* destination) {
    dynamsoft::ddn::CProcessedDocumentResult* documents =
        captured->GetProcessedDocumentResult();
    if (documents == nullptr) return;
    for (int index = 0; index < documents->GetDetectedQuadResultItemsCount(); ++index) {
      const dynamsoft::ddn::CDetectedQuadResultItem* item =
          documents->GetDetectedQuadResultItem(index);
      if (item == nullptr) continue;
      VisionDocumentDetection detection;
      detection.location = ToQuadrilateral(item->GetLocation());
      detection.confidence = item->GetConfidenceAsDocumentBoundary();
      destination->document_detections.push_back(std::move(detection));
    }
    documents->Release();
  }

  static VisionQuadrilateral ToQuadrilateral(const CQuadrilateral& quad) {
    VisionQuadrilateral result;
    for (int index = 0; index < 4; ++index) {
      result.coordinates[index * 2] = quad.points[index][0];
      result.coordinates[index * 2 + 1] = quad.points[index][1];
    }
    return result;
  }

  static ImagePixelFormat PixelFormatFromName(const std::string& format) {
    if (format == "binary") return IPF_BINARY;
    if (format == "grayscale") return IPF_GRAYSCALED;
    if (format == "nv21") return IPF_NV21;
    if (format == "nv12") return IPF_NV12;
    if (format == "rgb565") return IPF_RGB_565;
    if (format == "rgb555") return IPF_RGB_555;
    if (format == "rgb888") return IPF_RGB_888;
    if (format == "bgr888") return IPF_BGR_888;
    if (format == "argb8888") return IPF_ARGB_8888;
    if (format == "abgr8888") return IPF_ABGR_8888;
    throw VisionError(-1, "Unsupported image pixel format: " + format);
  }

  static std::string SafeString(const char* value) {
    return value == nullptr ? "" : std::string(value);
  }

  static std::string ErrorMessage(const char* message,
                                  const std::string& fallback) {
    return message == nullptr || message[0] == '\0' ? fallback : std::string(message);
  }

  void EnsureInitialized() const {
    if (!initialized_) {
      throw VisionError(-1, "Initialize Capture Vision before use.");
    }
  }

  CCaptureVisionRouter* router_;
  bool initialized_ = false;
  std::mutex mutex_;
};

}  // namespace flutter_capture_vision

#endif  // FLUTTER_CAPTURE_VISION_VISION_ROUTER_H_
