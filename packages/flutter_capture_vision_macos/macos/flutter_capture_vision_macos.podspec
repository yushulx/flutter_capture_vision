Pod::Spec.new do |s|
  s.name             = 'flutter_capture_vision_macos'
  s.version          = '0.1.0'
  s.summary          = 'Dynamsoft Capture Vision for Flutter on macOS.'
  s.description      = 'Barcode, MRZ, and document-boundary detection for Flutter macOS.'
  s.homepage         = 'https://github.com/yushulx/flutter_capture_vision'
  s.license          = { :type => 'Commercial' }
  s.author           = { 'Dynamsoft' => 'support@dynamsoft.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_capture_vision_macos/Sources/flutter_capture_vision_macos/**/*'
  # Only the registration header may be public: vision_router.h includes the
  # vendored DCV headers, which are not part of the built framework, and a
  # public umbrella reference would break the app target's module import.
  s.public_header_files = 'flutter_capture_vision_macos/Sources/flutter_capture_vision_macos/FlutterCaptureVisionPlugin.h'
  s.vendored_libraries = 'flutter_capture_vision_macos/Libraries/*.dylib'
  # Models/templates must be copied next to the dylibs in the final app
  # bundle (Contents/Frameworks). See the package README for the script.
  s.preserve_paths = 'flutter_capture_vision_macos/Resources'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/flutter_capture_vision_macos/Libraries"',
    'LIBRARY_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/flutter_capture_vision_macos/Libraries"',
    # Objective-C++ sources need an explicit framework link; unlike Swift,
    # they do not autolink FlutterMacOS through the module map.
    'OTHER_LDFLAGS' => '$(inherited) -framework FlutterMacOS',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
