import 'capture_vision_exception.dart';
import 'vision_task.dart';

/// Selects either built-in tasks or one exact DCV template name for a capture.
sealed class CaptureVisionRequest {
  const CaptureVisionRequest._();

  /// Requests one or more factory-default tasks.
  factory CaptureVisionRequest.forTasks(Iterable<VisionTask> tasks) {
    final normalizedTasks = Set<VisionTask>.unmodifiable(tasks);
    if (normalizedTasks.isEmpty) {
      throw const CaptureVisionException(
        code: 'empty_task_set',
        message: 'A capture request must include at least one vision task.',
      );
    }
    return DefaultTasksCaptureVisionRequest._(normalizedTasks);
  }

  /// Requests a template by its exact, case-sensitive DCV name.
  factory CaptureVisionRequest.namedTemplate(String templateName) {
    if (templateName.trim().isEmpty) {
      throw const CaptureVisionException(
        code: 'invalid_template_name',
        message: 'A named template request requires a non-empty template name.',
      );
    }
    return NamedTemplateCaptureVisionRequest._(templateName);
  }
}

/// A request composed from built-in Capture Vision tasks.
class DefaultTasksCaptureVisionRequest extends CaptureVisionRequest {
  const DefaultTasksCaptureVisionRequest._(this.tasks) : super._();

  /// The requested tasks, de-duplicated while preserving no ordering contract.
  final Set<VisionTask> tasks;
}

/// A request that passes [templateName] unchanged to CaptureVisionRouter.
class NamedTemplateCaptureVisionRequest extends CaptureVisionRequest {
  const NamedTemplateCaptureVisionRequest._(this.templateName) : super._();

  /// The exact, case-sensitive name declared in `CaptureVisionTemplates`.
  final String templateName;
}
