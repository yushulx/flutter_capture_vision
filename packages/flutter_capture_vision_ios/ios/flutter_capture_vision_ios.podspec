Pod::Spec.new do |s|
  s.name             = 'flutter_capture_vision_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS implementation of flutter_capture_vision.'
  s.description      = <<-DESC
An asynchronous Flutter bridge for Dynamsoft Capture Vision on iOS.
                       DESC
  s.homepage         = 'https://github.com/yushulx/flutter_capture_vision'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Dynamsoft' => 'support@dynamsoft.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_capture_vision_ios/Sources/flutter_capture_vision_ios/**/*'
  s.dependency 'Flutter'
  # The MRZ Scanner bundle is a superset of the Capture Vision bundle: it also
  # ships the MRZ neural models and a working built-in MRZ template, without
  # which the plain bundle's MRZ templates produce no results.
  s.dependency 'DynamsoftMRZScannerBundle', '3.4.1300'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
