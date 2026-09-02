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
    this.appVersion,
    this.buildNumber,
    this.releaseChannel,
    this.environment,
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
  final String? appVersion;
  final String? buildNumber;
  final String? releaseChannel;

  /// Which of the client's environments this came from.
  ///
  /// One `citadel-arm` database holds all four, distinguished by this rather
  /// than by four databases, because Citadel compares them: the same fault in
  /// staging and in production is one question. See DECISIONS.md 02/09/26.
  ///
  /// Distinct from [releaseChannel], which says which build somebody is
  /// running — a beta build in production and a stable build in staging are
  /// both ordinary, and one field could not say either.
  ///
  /// Null when the application does not set it. Read back as "not recorded"
  /// rather than as production: a filtered read excludes it instead of putting
  /// unknown-origin noise in front of somebody looking at a live incident.
  final String? environment;
  final bool handled;
}

abstract interface class ArmSink {
  Future<ArmCaptureResult> record(ArmCaptureRequest request);
}
