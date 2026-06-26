import 'arm_binary_attachment.dart';
import 'arm_capture_result.dart';
import 'arm_types.dart';

class ArmCaptureRequest {
  const ArmCaptureRequest({
    required this.severity,
    required this.category,
    required this.feature,
    required this.operation,
    required this.message,
    required this.errorType,
    required this.stackTrace,
    required this.fingerprint,
    required this.sessionId,
    required this.breadcrumbs,
    required this.context,
    required this.tags,
    this.errorName,
    this.errorData,
    this.recoverySnapshot,
    this.screenshot,
    this.handled = false,
  });

  final ArmSeverity severity;
  final String category;
  final String feature;
  final String operation;
  final String message;
  final String errorType;
  final String stackTrace;
  final String fingerprint;
  final String sessionId;
  final List<ArmBreadcrumb> breadcrumbs;
  final Map<String, dynamic> context;
  final Map<String, dynamic> tags;
  final String? errorName;
  final Map<String, dynamic>? errorData;
  final Map<String, dynamic>? recoverySnapshot;
  final ArmBinaryAttachment? screenshot;
  final bool handled;
}

abstract interface class ArmSink {
  Future<ArmCaptureResult> record(ArmCaptureRequest request);
}
