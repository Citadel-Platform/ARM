import 'arm_service_json.dart';
import 'arm_service_models.dart';

abstract interface class ArmEvidenceRepository {
  Future<ArmIssuePageSlice> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  });

  Future<ArmCasePageSlice> listCases({
    required String projectId,
    required ArmCaseQuery query,
  });

  Future<ArmCaseDetail?> getCaseDetail({
    required String projectId,
    required String caseId,
  });

  Future<ArmIssueRecord?> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatusMutation mutation,
  });

  Future<ArmCaseRecord?> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatusMutation mutation,
  });
}

final class ArmServiceException implements Exception {
  const ArmServiceException({
    required this.code,
    required this.message,
    this.retryable = false,
    this.details = const <String, String>{},
  });

  final ArmServiceErrorCode code;
  final String message;
  final bool retryable;
  final Map<String, String> details;
}

final class ArmPrivateService {
  const ArmPrivateService({required ArmEvidenceRepository repository})
    : _repository = repository;

  final ArmEvidenceRepository _repository;

  Future<ArmIssuePage> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  }) async {
    final target = _projectId(projectId);
    _validateIssueQuery(query);
    final slice = await _repository.listIssues(projectId: target, query: query);
    if (slice.issues.length > query.pageSize ||
        (slice.hasMore && slice.issues.isEmpty)) {
      throw _invalidRepositoryPage();
    }
    final issues = slice.issues.map(_validatedIssue).toList(growable: false)
      ..sort(_compareIssues);
    return ArmIssuePage(
      projectId: target,
      issues: issues,
      nextPageToken: slice.hasMore
          ? encodeArmPageToken(
              ArmPageCursor(
                timestamp: issues.last.lastSeenAt,
                documentId: issues.last.issueId,
              ),
            )
          : null,
    );
  }

  Future<ArmCasePage> listCases({
    required String projectId,
    required ArmCaseQuery query,
  }) async {
    final target = _projectId(projectId);
    _validateCaseQuery(query);
    final slice = await _repository.listCases(projectId: target, query: query);
    if (slice.cases.length > query.pageSize ||
        (slice.hasMore && slice.cases.isEmpty)) {
      throw _invalidRepositoryPage();
    }
    final cases = slice.cases.map(_validatedCase).toList(growable: false)
      ..sort(_compareCases);
    return ArmCasePage(
      projectId: target,
      cases: cases,
      nextPageToken: slice.hasMore
          ? encodeArmPageToken(
              ArmPageCursor(
                timestamp: cases.last.createdAt,
                documentId: cases.last.caseId,
              ),
            )
          : null,
    );
  }

  Future<ArmCaseDetail> getCaseDetail({
    required String projectId,
    required String caseId,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(caseId, 'caseId');
    final detail = await _repository.getCaseDetail(
      projectId: target,
      caseId: id,
    );
    if (detail == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM case was not found.',
      );
    }
    final caseRecord = _validatedCase(detail.caseRecord);
    final issue = _validatedIssue(detail.issue);
    if (detail.projectId != target ||
        caseRecord.caseId != id ||
        caseRecord.issueId != issue.issueId) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned inconsistent case detail.',
      );
    }
    return ArmCaseDetail(
      projectId: target,
      caseRecord: caseRecord,
      issue: issue,
    );
  }

  Future<ArmIssueRecord> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatus status,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(issueId, 'issueId');
    final updated = await _repository.updateIssueStatus(
      projectId: target,
      issueId: id,
      mutation: ArmIssueStatusMutation(
        status: status,
        updatedBy: _operatorEmail(principal),
      ),
    );
    if (updated == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM issue was not found.',
      );
    }
    final validated = _validatedIssue(updated);
    if (validated.issueId != id || validated.status != status) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an inconsistent issue update.',
      );
    }
    return validated;
  }

  Future<ArmCaseRecord> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatus status,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(caseId, 'caseId');
    final updated = await _repository.updateCaseStatus(
      projectId: target,
      caseId: id,
      mutation: ArmCaseStatusMutation(
        status: status,
        updatedBy: _operatorEmail(principal),
      ),
    );
    if (updated == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM case was not found.',
      );
    }
    final validated = _validatedCase(updated);
    if (validated.caseId != id || validated.status != status) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an inconsistent case update.',
      );
    }
    return validated;
  }

  void _validateIssueQuery(ArmIssueQuery query) {
    _pageSize(query.pageSize);
    _utcOrNull(query.since, 'since');
    _cursor(query.cursor);
  }

  void _validateCaseQuery(ArmCaseQuery query) {
    _pageSize(query.pageSize);
    _utcOrNull(query.since, 'since');
    _cursor(query.cursor);
    if (query.issueId != null) {
      _resourceId(query.issueId!, 'issueId');
    }
  }

  void _pageSize(int value) {
    if (value < 1 || value > armMaximumPageSize) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: 'pageSize must be between 1 and 100.',
      );
    }
  }

  void _cursor(ArmPageCursor? value) {
    if (value == null) {
      return;
    }
    _utc(value.timestamp, 'pageToken.timestamp');
    _resourceId(value.documentId, 'pageToken.documentId');
  }

  String _projectId(String value) => _resourceId(value, 'projectId');

  String _resourceId(String value, String field) {
    try {
      return validateArmResourceId(value, fieldName: field);
    } on FormatException {
      throw ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: '$field is invalid.',
      );
    }
  }

  String _operatorEmail(ArmAuthorizedPrincipal principal) {
    final actorId = principal.actorId.trim();
    final email = principal.actorEmail?.trim().toLowerCase();
    if (actorId.isEmpty ||
        email == null ||
        email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.permissionDenied,
        message: 'Authorized operator identity is incomplete.',
      );
    }
    return email;
  }

  ArmIssueRecord _validatedIssue(ArmIssueRecord value) {
    try {
      return decodeArmIssueRecord(encodeArmIssueRecord(value));
    } on FormatException {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an invalid issue record.',
      );
    }
  }

  ArmCaseRecord _validatedCase(ArmCaseRecord value) {
    try {
      return decodeArmCaseRecord(encodeArmCaseRecord(value));
    } on FormatException {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an invalid case record.',
      );
    }
  }

  void _utcOrNull(DateTime? value, String field) {
    if (value != null) {
      _utc(value, field);
    }
  }

  void _utc(DateTime value, String field) {
    if (!value.isUtc) {
      throw ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: '$field must be UTC.',
      );
    }
  }

  int _compareIssues(ArmIssueRecord left, ArmIssueRecord right) {
    final timestamp = right.lastSeenAt.compareTo(left.lastSeenAt);
    return timestamp != 0 ? timestamp : right.issueId.compareTo(left.issueId);
  }

  int _compareCases(ArmCaseRecord left, ArmCaseRecord right) {
    final timestamp = right.createdAt.compareTo(left.createdAt);
    return timestamp != 0 ? timestamp : right.caseId.compareTo(left.caseId);
  }

  ArmServiceException _invalidRepositoryPage() => const ArmServiceException(
    code: ArmServiceErrorCode.internal,
    message: 'ARM repository returned an invalid page.',
  );
}
