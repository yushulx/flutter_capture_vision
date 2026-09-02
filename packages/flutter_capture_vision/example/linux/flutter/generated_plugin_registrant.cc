//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <file_saver/file_saver_plugin.h>
#include <file_selector_linux/file_selector_plugin.h>
#include <flutter_capture_vision_linux/flutter_capture_vision_plugin.h>
#include <flutter_lite_camera/flutter_lite_camera_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) file_saver_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSaverPlugin");
  file_saver_plugin_register_with_registrar(file_saver_registrar);
  g_autoptr(FlPluginRegistrar) file_selector_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSelectorPlugin");
  file_selector_plugin_register_with_registrar(file_selector_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_capture_vision_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterCaptureVisionPlugin");
  flutter_capture_vision_plugin_register_with_registrar(flutter_capture_vision_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_lite_camera_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterLiteCameraPlugin");
  flutter_lite_camera_plugin_register_with_registrar(flutter_lite_camera_registrar);
  g_autoptr(FlPluginRegistrar) url_launcher_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_linux_registrar);
}
