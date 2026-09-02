#ifndef FLUTTER_PLUGIN_FLUTTER_CAPTURE_VISION_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_CAPTURE_VISION_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

G_DECLARE_FINAL_TYPE(FlutterCaptureVisionPlugin, flutter_capture_vision_plugin,
                     FLUTTER, CAPTURE_VISION_PLUGIN, GObject)

FLUTTER_PLUGIN_EXPORT void flutter_capture_vision_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

#endif  // FLUTTER_PLUGIN_FLUTTER_CAPTURE_VISION_PLUGIN_H_
