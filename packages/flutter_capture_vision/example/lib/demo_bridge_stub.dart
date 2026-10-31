/// Native / non-web fallback for [resolveDemoLicenseKey] and the analytics hooks.
///
/// A desktop or mobile build has no hosting page to inject a key, so it uses the
/// public Dynamsoft Capture Vision trial key. Replace it with your own license
/// for anything beyond local experiments.
const String kTrialLicenseKey =
    'DLS2eyJoYW5kc2hha2VDb2RlIjoiMjAwMDAxLTE2NDk4Mjk3OTI2MzUiLCJvcmdhbml6YXRpb25JRCI6IjIwMDAwMSIsInNlc3Npb25QYXNzd29yZCI6IndTcGR6Vm05WDJrcEQ5YUoifQ==';

/// Returns the license key used by `FlutterCaptureVision.initialize`.
String resolveDemoLicenseKey() => kTrialLicenseKey;

/// No-op on native platforms: analytics only exists in the hosted web demo.
void reportDemoReady(int loadMs) {}

/// No-op on native platforms.
void reportDemoError(String code, String message) {}

/// No-op on native platforms.
void reportDemoScanStart(String mode, String inputSource) {}

/// No-op on native platforms.
void reportDemoScanSuccess(String mode, String inputSource) {}

/// No-op on native platforms.
void reportDemoScanFail(String mode, String inputSource) {}

/// No-op on native platforms.
void reportDemoAction(String name, [Map<String, Object?>? params]) {}
