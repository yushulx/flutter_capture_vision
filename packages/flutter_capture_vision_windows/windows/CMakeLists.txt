cmake_minimum_required(VERSION 3.15)
project(flutter_capture_vision_windows LANGUAGES CXX)

set(PLUGIN_NAME "flutter_capture_vision_windows_plugin")
add_library(${PLUGIN_NAME} SHARED "flutter_capture_vision_plugin.cpp")
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_compile_options(${PLUGIN_NAME} PRIVATE /wd4121 /W3 /WX-)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_directories(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/lib")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  DynamsoftCorex64 DynamsoftLicensex64 DynamsoftCaptureVisionRouterx64
  DynamsoftUtilityx64 DynamsoftBarcodeReaderx64 DynamsoftLabelRecognizerx64
  DynamsoftDocumentNormalizerx64 DynamsoftCodeParserx64
  DynamsoftCodeParserDedicatorx64 DynamsoftIdentityUtilityx64
  DynamsoftImageProcessingx64 DynamsoftNeuralNetworkx64)

# Flutter copies every item in this list beside the runner executable.  The
# resource directory is intentionally bundled with this Windows-only package.
set(flutter_capture_vision_windows_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/"
  "${CMAKE_CURRENT_SOURCE_DIR}/../resources/"
  PARENT_SCOPE
)
