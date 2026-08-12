import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'arm_service_models.freezed.dart';

const int armDefaultPageSize = 25;
const int armMaximumPageSize = 100;

enum ArmIssueStatus {
  open,
  investigating,
  triaging,
  monitoring,
  resolved,
  closed,
}

enum ArmCaseStatus {
  newCase,
  acknowledged,
  triaging,
  monitoring,
  resolved,
  closed,
}

enum ArmPrivateOperation {
  listIssues,
  listCases,
  getCaseDetail,
  updateIssueStatus,
  updateCaseStatus,
}

enum ArmServiceErrorCode {
  invalidArgument,
  unauthenticated,
  permissionDenied,
  notFound,
  failedPrecondition,
  unavailable,
  internal,
}

@freezed
abstract class ArmPageCursor with _$ArmPageCursor {
  const factory ArmPageCursor({
    required DateTime timestamp,
    required String documentId,
  }) = _ArmPageCursor;
}

@freezed
abstract class ArmIssueRecord with _$ArmIssueRecord {
  const factory ArmIssueRecord({
    required String issueId,
    required String severity,
    required String category,
    required String feature,
    required String operation,
    required DateTime firstSeenAt,
    required DateTime lastSeenAt,
    required int caseCount,
    String? firstCaseId,
    String? lastCaseId,
    ArmIssueStatus? status,
    String? appVersion,
    String? buildNumber,
    String? releaseChannel,
  }) = _ArmIssueRecord;
}

@freezed
abstract class ArmCaseRecord with _$ArmCaseRecord {
  const factory ArmCaseRecord({
    required String caseId,
    required String issueId,
    required String fingerprint,
    required String severity,
    required String category,
    required String feature,
    required String operation,
    required String message,
    required String errorType,
    required String stackTrace,
    required String sessionId,
    required bool handled,
    required DateTime createdAt,
    @Default(<String, Object?>{}) Map<String, Object?> context,
    @Default(<String, Object?>{}) Map<String, Object?> tags,
    @Default(<Map<String, Object?>>[]) List<Map<String, Object?>> breadcrumbs,
    String? errorName,
    Map<String, Object?>? errorData,
    Map<String, Object?>? recoverySnapshot,
    Map<String, Object?>? screenshot,
    ArmCaseStatus? status,
    String? appVersion,
    String? buildNumber,
    String? releaseChannel,
  }) = _ArmCaseRecord;
}

@freezed
abstract class ArmIssueQuery with _$ArmIssueQuery {
  const factory ArmIssueQuery({
    DateTime? since,
    @Default(armDefaultPageSize) int pageSize,
    ArmPageCursor? cursor,
  }) = _ArmIssueQuery;
}

@freezed
abstract class ArmCaseQuery with _$ArmCaseQuery {
  const factory ArmCaseQuery({
    DateTime? since,
    String? issueId,
    @Default(armDefaultPageSize) int pageSize,
    ArmPageCursor? cursor,
  }) = _ArmCaseQuery;
}

@freezed
abstract class ArmIssuePage with _$ArmIssuePage {
  const factory ArmIssuePage({
    required String projectId,
    @Default(<ArmIssueRecord>[]) List<ArmIssueRecord> issues,
    String? nextPageToken,
  }) = _ArmIssuePage;
}

@freezed
abstract class ArmCasePage with _$ArmCasePage {
  const factory ArmCasePage({
    required String projectId,
    @Default(<ArmCaseRecord>[]) List<ArmCaseRecord> cases,
    String? nextPageToken,
  }) = _ArmCasePage;
}

@freezed
abstract class ArmIssuePageSlice with _$ArmIssuePageSlice {
  const factory ArmIssuePageSlice({
    @Default(<ArmIssueRecord>[]) List<ArmIssueRecord> issues,
    @Default(false) bool hasMore,
  }) = _ArmIssuePageSlice;
}

@freezed
abstract class ArmCasePageSlice with _$ArmCasePageSlice {
  const factory ArmCasePageSlice({
    @Default(<ArmCaseRecord>[]) List<ArmCaseRecord> cases,
    @Default(false) bool hasMore,
  }) = _ArmCasePageSlice;
}

@freezed
abstract class ArmCaseDetail with _$ArmCaseDetail {
  const factory ArmCaseDetail({
    required String projectId,
    required ArmCaseRecord caseRecord,
    required ArmIssueRecord issue,
  }) = _ArmCaseDetail;
}

@freezed
abstract class ArmIssueStatusPatch with _$ArmIssueStatusPatch {
  const factory ArmIssueStatusPatch({required ArmIssueStatus status}) =
      _ArmIssueStatusPatch;
}

@freezed
abstract class ArmCaseStatusPatch with _$ArmCaseStatusPatch {
  const factory ArmCaseStatusPatch({required ArmCaseStatus status}) =
      _ArmCaseStatusPatch;
}

@freezed
abstract class ArmAuthorizedPrincipal with _$ArmAuthorizedPrincipal {
  const factory ArmAuthorizedPrincipal({
    required String actorId,
    String? actorEmail,
  }) = _ArmAuthorizedPrincipal;
}

@freezed
abstract class ArmAuthorizationRequest with _$ArmAuthorizationRequest {
  const factory ArmAuthorizationRequest({
    required String requestId,
    required ArmPrivateOperation operation,
    required String projectId,
    required String authorizationHeader,

    /// Actor coordinates forwarded by the calling Platform API. They are only
    /// trustworthy once the caller itself has been verified.
    String? forwardedActorId,
    String? forwardedActorEmail,
  }) = _ArmAuthorizationRequest;
}

@freezed
abstract class ArmIssueStatusMutation with _$ArmIssueStatusMutation {
  const factory ArmIssueStatusMutation({
    required ArmIssueStatus status,
    required String updatedBy,
    @Default('citadel_platform_operator') String statusSource,
  }) = _ArmIssueStatusMutation;
}

/// An operator's triage decision on a case.
///
/// It deliberately carries no `handled` flag. Whether the application caught
/// the error is capture evidence recorded at the boundary; overwriting it from
/// a triage command would destroy that record.
@freezed
abstract class ArmCaseStatusMutation with _$ArmCaseStatusMutation {
  const factory ArmCaseStatusMutation({
    required ArmCaseStatus status,
    required String updatedBy,
    @Default('citadel_platform_operator') String statusSource,
  }) = _ArmCaseStatusMutation;
}

@freezed
abstract class ArmServiceError with _$ArmServiceError {
  const factory ArmServiceError({
    required ArmServiceErrorCode code,
    required String message,
    required String requestId,
    @Default(false) bool retryable,
    @Default(<String, String>{}) Map<String, String> details,
  }) = _ArmServiceError;
}

typedef ArmPrivateRequestAuthorizer =
    FutureOr<ArmAuthorizedPrincipal?> Function(ArmAuthorizationRequest request);
