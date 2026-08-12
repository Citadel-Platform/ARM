import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:googleapis_auth/auth_io.dart';

class FirestoreServiceAccountArmSink implements ArmSink {
  FirestoreServiceAccountArmSink._({
    required this.projectId,
    required AutoRefreshingAuthClient? authClient,
    required firestore_api.FirestoreApi firestoreApi,
    required this.issuesCollection,
    required this.casesCollection,
    required this.caseIdExposureThreshold,
  }) : _authClient = authClient,
       _firestoreApi = firestoreApi;

  /// Builds a sink over an already-authenticated Firestore client.
  ///
  /// Exposed so the exact write shape can be asserted without a real service
  /// account: the fields and update mask this sink sends determine whether
  /// operator-owned triage state survives a recurrence.
  factory FirestoreServiceAccountArmSink.withFirestoreApi({
    required String projectId,
    required firestore_api.FirestoreApi firestoreApi,
    String issuesCollection = 'armIssues',
    String casesCollection = 'armCases',
    ArmSeverity caseIdExposureThreshold = ArmSeverity.moderate,
  }) {
    return FirestoreServiceAccountArmSink._(
      projectId: projectId,
      authClient: null,
      firestoreApi: firestoreApi,
      issuesCollection: issuesCollection,
      casesCollection: casesCollection,
      caseIdExposureThreshold: caseIdExposureThreshold,
    );
  }

  final String projectId;
  final AutoRefreshingAuthClient? _authClient;
  final firestore_api.FirestoreApi _firestoreApi;
  final String issuesCollection;
  final String casesCollection;
  final ArmSeverity caseIdExposureThreshold;

  String get _documentsRoot =>
      'projects/$projectId/databases/(default)/documents';

  static Future<FirestoreServiceAccountArmSink> fromServiceAccountJson({
    required Map<String, Object?> serviceAccount,
    String issuesCollection = 'armIssues',
    String casesCollection = 'armCases',
    ArmSeverity caseIdExposureThreshold = ArmSeverity.moderate,
  }) async {
    final credentials = ServiceAccountCredentials.fromJson(serviceAccount);
    final authClient = await clientViaServiceAccount(credentials, <String>[
      firestore_api.FirestoreApi.datastoreScope,
    ]);
    return FirestoreServiceAccountArmSink._(
      projectId: serviceAccount['project_id'] as String,
      authClient: authClient,
      firestoreApi: firestore_api.FirestoreApi(authClient),
      issuesCollection: issuesCollection,
      casesCollection: casesCollection,
      caseIdExposureThreshold: caseIdExposureThreshold,
    );
  }

  @override
  Future<ArmCaptureResult> record(ArmCaptureRequest request) async {
    final issueId = buildArmIssueId(request.fingerprint);
    final caseId = buildArmCaseId();
    // Written as a DateTime so Firestore stores a real timestampValue. ISO
    // strings sort as strings, and Firestore orders by value type before value,
    // so a collection holding both cannot be ordered or paged on these fields.
    final now = DateTime.now().toUtc();
    final issueName = '$_documentsRoot/$issuesCollection/$issueId';
    final caseName = '$_documentsRoot/$casesCollection/$caseId';

    final existingIssue = await _tryGetDocument(issueName);
    final caseCount = _intFromValue(existingIssue?.fields?['caseCount']) + 1;
    final firstSeenAt =
        _timestampFromValue(existingIssue?.fields?['firstSeenAt']) ?? now;
    final firstCaseId =
        _stringFromValue(existingIssue?.fields?['firstCaseId']) ?? caseId;

    await _upsertDocument(
      issueName,
      buildArmIssueDocumentMap(
        issueId: issueId,
        caseId: caseId,
        request: request,
        firstSeenAt: firstSeenAt,
        lastSeenAt: now,
        firstCaseId: firstCaseId,
        caseCount: caseCount,
      ),
    );
    await _upsertDocument(
      caseName,
      buildArmCaseDocumentMap(
        caseId: caseId,
        issueId: issueId,
        request: request,
        createdAt: now,
      ),
    );

    return ArmCaptureResult(
      caseId: caseId,
      issueId: issueId,
      fingerprint: request.fingerprint,
      severity: request.severity,
      caseIdExposed: request.severity.index >= caseIdExposureThreshold.index,
    );
  }

  Future<firestore_api.Document?> _tryGetDocument(String name) async {
    try {
      return await _firestoreApi.projects.databases.documents.get(name);
    } catch (_) {
      return null;
    }
  }

  /// Writes exactly the capture-owned fields.
  ///
  /// A patch without an update mask replaces the whole document, which would
  /// erase operator-owned triage fields such as `status`, `statusUpdatedBy`,
  /// and `statusUpdatedAt` every time the same issue recurred.
  Future<void> _upsertDocument(
    String name,
    Map<String, dynamic> payload,
  ) async {
    await _firestoreApi.projects.databases.documents.patch(
      firestore_api.Document(
        name: name,
        fields: payload.map(
          (key, value) => MapEntry(key, _toFirestoreValue(value)),
        ),
      ),
      name,
      updateMask_fieldPaths: payload.keys
          .map(_escapeFieldPath)
          .toList(growable: false),
    );
  }

  void close() {
    _authClient?.close();
  }
}

firestore_api.Value _toFirestoreValue(Object? value) {
  if (value == null) {
    return firestore_api.Value(nullValue: 'NULL_VALUE');
  }
  if (value is bool) {
    return firestore_api.Value(booleanValue: value);
  }
  if (value is int) {
    return firestore_api.Value(integerValue: value.toString());
  }
  if (value is double) {
    return firestore_api.Value(doubleValue: value);
  }
  if (value is num) {
    return firestore_api.Value(doubleValue: value.toDouble());
  }
  if (value is DateTime) {
    return firestore_api.Value(timestampValue: value.toUtc().toIso8601String());
  }
  if (value is String) {
    return firestore_api.Value(stringValue: value);
  }
  if (value is Iterable) {
    return firestore_api.Value(
      arrayValue: firestore_api.ArrayValue(
        values: value
            .map((item) => _toFirestoreValue(item))
            .toList(growable: false),
      ),
    );
  }
  if (value is Map) {
    final fields = <String, firestore_api.Value>{};
    for (final entry in value.entries) {
      fields[entry.key.toString()] = _toFirestoreValue(entry.value);
    }
    return firestore_api.Value(
      mapValue: firestore_api.MapValue(fields: fields),
    );
  }
  return firestore_api.Value(stringValue: value.toString());
}

int _intFromValue(firestore_api.Value? value) {
  if (value == null) {
    return 0;
  }
  if (value.integerValue != null) {
    return int.tryParse(value.integerValue!) ?? 0;
  }
  if (value.doubleValue != null) {
    return value.doubleValue!.toInt();
  }
  return 0;
}

String? _stringFromValue(firestore_api.Value? value) {
  if (value == null) {
    return null;
  }
  return value.stringValue ?? value.timestampValue;
}

/// Reads a timestamp that earlier SDK versions may have stored as a string.
DateTime? _timestampFromValue(firestore_api.Value? value) {
  final raw = value?.timestampValue ?? value?.stringValue;
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

/// Quotes a field path segment unless it is a plain identifier.
String _escapeFieldPath(String field) {
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(field)
      ? field
      : '`${field.replaceAll(r'\', r'\\').replaceAll('`', r'\`')}`';
}
