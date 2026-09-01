/// A stable error raised by the Capture Vision Dart API.
class CaptureVisionException implements Exception {
  /// Creates an exception with a machine-readable [code].
  const CaptureVisionException({
    required this.code,
    required this.message,
    this.cause,
  });

  /// A stable identifier that callers can handle without parsing [message].
  final String code;

  /// A user-facing explanation that does not expose native stack traces.
  final String message;

  /// The original error when it is safe to retain it for local diagnostics.
  final Object? cause;

  @override
  String toString() => 'CaptureVisionException($code): $message';
}
