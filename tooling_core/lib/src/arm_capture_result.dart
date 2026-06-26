import 'package:meta/meta.dart';

import 'arm_types.dart';

@immutable
class ArmCaptureResult {
  const ArmCaptureResult({
    required this.caseId,
    required this.issueId,
    required this.fingerprint,
    required this.severity,
    required this.caseIdExposed,
  });

  final String caseId;
  final String issueId;
  final String fingerprint;
  final ArmSeverity severity;
  final bool caseIdExposed;
}
