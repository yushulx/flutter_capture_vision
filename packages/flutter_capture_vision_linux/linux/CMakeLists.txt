cmake_minimum_required(VERSION 3.10)
project(flutter_capture_vision_linux LANGUAGES CXX)

set(PLUGIN_NAME "flutter_capture_vision_linux_plugin")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(DCV_ARCH "arm64")
else()
  set(DCV_ARCH "x64")
endif()

add_library(${PLUGIN_NAME} SHARED "flutter_capture_vision_plugin.cc")
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_directories(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/lib/${DCV_ARCH}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK
  DynamsoftCore DynamsoftLicense DynamsoftCaptureVisionRouter DynamsoftUtility
  DynamsoftBarcodeReader DynamsoftLabelRecognizer DynamsoftDocumentNormalizer
  DynamsoftCodeParser DynamsoftCodeParserDedicator DynamsoftIdentityUtility
  DynamsoftImageProcessing DynamsoftNeuralNetwork)
# DynamicPdf is deliberately not linked: the plugin never calls its API and
# libDynamicPdf.so carries a versioned dependency (libDynamicPdfR_*.so) that
# is not shipped, which breaks the executable link step. DCV loads the PDF
# module on demand when a PDF file is actually captured.
set_target_properties(${PLUGIN_NAME} PROPERTIES INSTALL_RPATH "$ORIGIN" BUILD_RPATH "$ORIGIN")

file(GLOB DCV_SHARED_LIBRARIES "${CMAKE_CURRENT_SOURCE_DIR}/lib/${DCV_ARCH}/*.so")
set(flutter_capture_vision_linux_bundled_libraries ${DCV_SHARED_LIBRARIES} PARENT_SCOPE)

# DCV resolves models, presets, parser resources, and character-confusion
# data relative to its installed shared libraries. The resources set lives at
# the package root (sibling of linux/), as in the Windows plugin's CMake.
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../resources/" DESTINATION "lib/")
