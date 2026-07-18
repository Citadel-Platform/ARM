import 'arm_sink.dart';
import 'arm_types.dart';

Map<String, dynamic> buildArmIssueDocumentMap({
  required String issueId,
  required String caseId,
  required ArmCaptureRequest request,
  required Object firstSeenAt,
  required Object lastSeenAt,
  required String firstCaseId,
  required int caseCount,
}) {
  return <String, dynamic>{
    'issueId': issueId,
    'severity': request.severity.wireName,
    'category': request.category,
    'feature': request.feature,
    'operation': request.operation,
    'firstSeenAt': firstSeenAt,
    'firstCaseId': firstCaseId,
    'lastSeenAt': lastSeenAt,
    'lastCaseId': caseId,
    'caseCount': caseCount,
    if (request.appVersion != null) 'appVersion': request.appVersion,
    if (request.buildNumber != null) 'buildNumber': request.buildNumber,
    if (request.releaseChannel != null)
      'releaseChannel': request.releaseChannel,
  };
}

Map<String, dynamic> buildArmCaseDocumentMap({
  required String caseId,
  required String issueId,
  required ArmCaptureRequest request,
  required Object createdAt,
  String? screenshotPath,
}) {
  return <String, dynamic>{
    'caseId': caseId,
    'issueId': issueId,
    'fingerprint': request.fingerprint,
    'severity': request.severity.wireName,
    'category': request.category,
    'feature': request.feature,
    'operation': request.operation,
    'message': request.message,
    'errorType': request.errorType,
    if (request.errorName != null) 'errorName': request.errorName,
    if (request.errorData != null && request.errorData!.isNotEmpty)
      'errorData': request.errorData,
    'stackTrace': request.stackTrace,
    'sessionId': request.sessionId,
    'handled': request.handled,
    if (request.appVersion != null) 'appVersion': request.appVersion,
    if (request.buildNumber != null) 'buildNumber': request.buildNumber,
    if (request.releaseChannel != null)
      'releaseChannel': request.releaseChannel,
    'context': request.context,
    'tags': request.tags,
    'breadcrumbs': request.breadcrumbs.map((item) => item.toMap()).toList(),
    if (request.recoverySnapshot != null)
      'recoverySnapshot': request.recoverySnapshot,
    if (screenshotPath != null && request.screenshot != null)
      'screenshot': <String, dynamic>{
        'path': screenshotPath,
        'contentType': request.screenshot!.contentType,
      },
    'createdAt': createdAt,
  };
}
