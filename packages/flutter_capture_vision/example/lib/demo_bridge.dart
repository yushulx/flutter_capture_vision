/// License and analytics bridge for the example app.
///
/// `web/index.html` injects `window.FLUTTER_CAPTURE_VISION_LICENSE`; native
/// builds fall back to the trial key compiled into `demo_bridge_stub.dart`.
///
/// The hosted demo at dynamsoft.com/codepool/demos/flutter-capture-vision-scanner/
/// renders this app in an iframe, so the analytics hooks also reach the parent
/// page's `window.DemoAnalytics` (see `demos/shared/analytics.js`). Outside that
/// page every hook is a no-op.
library;

export 'demo_bridge_stub.dart'
    if (dart.library.js_interop) 'demo_bridge_web.dart';
