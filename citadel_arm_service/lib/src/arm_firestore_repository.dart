import 'package:googleapis/firestore/v1.dart' as firestore_api;

import 'arm_private_service.dart';
import 'arm_project_router.dart';
import 'arm_service_models.dart';

const String armIssuesCollectionId = 'armIssues';
const String armCasesCollectionId = 'armCases';

/// Upper bound on documents read from one customer collection for a single
/// request. ARM evidence written by the SDK carries mixed `timestampValue` and
/// `stringValue` timestamps, so the boundary cannot be ordered or paged inside
/// Firestore; it is ordered here instead. The scan is bounded rather than
/// silently truncated so a collection that outgrows it fails loudly.
const int armDefaultMaxScanDocuments = 5000;

const int _firestorePageSize = 300;

/// Reads and updates ARM evidence in the customer Firestore boundary.
final class FirestoreArmEvidenceRepository implements ArmEvidenceRepository {
  FirestoreArmEvidenceRepository({
    required firestore_api.FirestoreApi firestoreApi,
    required ArmProjectRouter router,
    this.maxScanDocuments = armDefaultMaxScanDocuments,
    DateTime Function()? clock,
  }) : _firestoreApi = firestoreApi,
       _router = router,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final firestore_api.FirestoreApi _firestoreApi;
  final ArmProjectRouter _router;
  final int maxScanDocuments;
  final DateTime Function() _clock;

  @override
  Future<ArmIssuePageSlice> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  }) async {
    final target = await _router.resolve(projectId);
    final documents = await _scanCollection(target, armIssuesCollectionId);
    final records = <ArmIssueRecord>[];
    for (final document in documents) {
      final record = _issueRecord(document);
      if (record == null) continue;
      if (query.since != null && record.lastSeenAt.isBefore(query.since!)) {
        continue;
      }
      records.add(record);
    }
    records.sort(
      (left, right) => _compare(
        right.lastSeenAt,
        right.issueId,
        left.lastSeenAt,
        left.issueId,
      ),
    );

    final page = _slice<ArmIssueRecord>(
      records: records,
      cursor: query.cursor,
      pageSize: query.pageSize,
      timestampOf: (record) => record.lastSeenAt,
      idOf: (record) => record.issueId,
    );
    return ArmIssuePageSlice(issues: page.items, hasMore: page.hasMore);
  }

  @override
  Future<ArmCasePageSlice> listCases({
    required String projectId,
    required ArmCaseQuery query,
  }) async {
    final target = await _router.resolve(projectId);
    final documents = await _scanCollection(target, armCasesCollectionId);
    final records = <ArmCaseRecord>[];
    for (final document in documents) {
      final record = _caseRecord(document);
      if (record == null) continue;
      if (query.since != null && record.createdAt.isBefore(query.since!)) {
        continue;
      }
      if (query.issueId != null && record.issueId != query.issueId) {
        continue;
      }
      records.add(record);
    }
    records.sort(
      (left, right) => _compare(
        right.createdAt,
        right.caseId,
        left.createdAt,
        left.caseId,
      ),
    );

    final page = _slice<ArmCaseRecord>(
      records: records,
      cursor: query.cursor,
      pageSize: query.pageSize,
      timestampOf: (record) => record.createdAt,
      idOf: (record) => record.caseId,
    );
    return ArmCasePageSlice(cases: page.items, hasMore: page.hasMore);
  }

  @override
  Future<ArmCaseDetail?> getCaseDetail({
    required String projectId,
    required String caseId,
  }) async {
    final target = await _router.resolve(projectId);
    final caseDocument = await _getDocument(
      '${target.documentsRoot}/$armCasesCollectionId/$caseId',
    );
    final caseRecord = caseDocument == null ? null : _caseRecord(caseDocument);
    if (caseRecord == null) {
      return null;
    }
    final issueDocument = await _getDocument(
      '${target.documentsRoot}/$armIssuesCollectionId/${caseRecord.issueId}',
    );
    final issue = issueDocument == null ? null : _issueRecord(issueDocument);
    if (issue == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'The ARM issue for this case was not found.',
      );
    }
    return ArmCaseDetail(
      projectId: projectId,
      caseRecord: caseRecord,
      issue: issue,
    );
  }

  @override
  Future<ArmIssueRecord?> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatusMutation mutation,
  }) async {
    final target = await _router.resolve(projectId);
    final name = '${target.documentsRoot}/$armIssuesCollectionId/$issueId';
    final updated = await _patchStatus(
      name: name,
      fields: <String, firestore_api.Value>{
        'status': firestore_api.Value(stringValue: mutation.status.name),
        'statusUpdatedAt': firestore_api.Value(
          timestampValue: _clock().toIso8601String(),
        ),
        'statusUpdatedBy': firestore_api.Value(
          stringValue: mutation.updatedBy,
        ),
        'statusSource': firestore_api.Value(
          stringValue: mutation.statusSource,
        ),
      },
    );
    if (updated == null) {
      return null;
    }
    final record = _issueRecord(updated);
    if (record == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'The updated ARM issue document is not readable.',
      );
    }
    return record;
  }

  @override
  Future<ArmCaseRecord?> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatusMutation mutation,
  }) async {
    final target = await _router.resolve(projectId);
    final name = '${target.documentsRoot}/$armCasesCollectionId/$caseId';
    final updated = await _patchStatus(
      name: name,
      fields: <String, firestore_api.Value>{
        'status': firestore_api.Value(
          stringValue: _caseStatusWireName(mutation.status),
        ),
        'handled': firestore_api.Value(booleanValue: mutation.handled),
        'statusUpdatedAt': firestore_api.Value(
          timestampValue: _clock().toIso8601String(),
        ),
        'statusUpdatedBy': firestore_api.Value(
          stringValue: mutation.updatedBy,
        ),
        'statusSource': firestore_api.Value(
          stringValue: mutation.statusSource,
        ),
      },
    );
    if (updated == null) {
      return null;
    }
    final record = _caseRecord(updated);
    if (record == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'The updated ARM case document is not readable.',
      );
    }
    return record;
  }

  Future<firestore_api.Document?> _patchStatus({
    required String name,
    required Map<String, firestore_api.Value> fields,
  }) async {
    try {
      return await _firestoreApi.projects.databases.documents.patch(
        firestore_api.Document(name: name, fields: fields),
        name,
        updateMask_fieldPaths: fields.keys.toList(growable: false),
        currentDocument_exists: true,
      );
    } on firestore_api.DetailedApiRequestError catch (error) {
      if (error.status == 404 || error.status == 400) {
        return null;
      }
      throw _upstreamFailure(error);
    }
  }

  Future<firestore_api.Document?> _getDocument(String name) async {
    try {
      return await _firestoreApi.projects.databases.documents.get(name);
    } on firestore_api.DetailedApiRequestError catch (error) {
      if (error.status == 404) {
        return null;
      }
      throw _upstreamFailure(error);
    }
  }

  Future<List<firestore_api.Document>> _scanCollection(
    ArmProjectTarget target,
    String collectionId,
  ) async {
    final documents = <firestore_api.Document>[];
    String? pageToken;
    do {
      final firestore_api.ListDocumentsResponse response;
      try {
        response = await _firestoreApi.projects.databases.documents.list(
          target.documentsRoot,
          collectionId,
          pageSize: _firestorePageSize,
          pageToken: pageToken,
        );
      } on firestore_api.DetailedApiRequestError catch (error) {
        throw _upstreamFailure(error);
      }
      documents.addAll(response.documents ?? const <firestore_api.Document>[]);
      pageToken = response.nextPageToken;
      if (documents.length > maxScanDocuments) {
        throw ArmServiceException(
          code: ArmServiceErrorCode.failedPrecondition,
          message:
              'The $collectionId collection exceeds the $maxScanDocuments '
              'document scan limit for ${target.customerProjectId}.',
        );
      }
    } while (pageToken != null && pageToken.isNotEmpty);
    return documents;
  }

  ArmServiceException _upstreamFailure(
    firestore_api.DetailedApiRequestError error,
  ) {
    if (error.status == 403 || error.status == 401) {
      return const ArmServiceException(
        code: ArmServiceErrorCode.permissionDenied,
        message:
            'The ARM evidence runtime is not authorized on the customer '
            'Firestore boundary.',
      );
    }
    return const ArmServiceException(
      code: ArmServiceErrorCode.unavailable,
      message: 'The customer Firestore boundary is unavailable.',
      retryable: true,
    );
  }

  ArmIssueRecord? _issueRecord(firestore_api.Document document) {
    final fields = document.fields ?? const <String, firestore_api.Value>{};
    final issueId = _resourceId(fields['issueId']) ?? _documentId(document);
    final lastSeenAt = _timestamp(fields['lastSeenAt']);
    if (issueId == null || lastSeenAt == null) {
      return null;
    }
    return ArmIssueRecord(
      issueId: issueId,
      severity: _text(fields['severity'], fallback: 'unknown'),
      category: _text(fields['category']),
      feature: _text(fields['feature']),
      operation: _text(fields['operation']),
      firstSeenAt: _timestamp(fields['firstSeenAt']) ?? lastSeenAt,
      lastSeenAt: lastSeenAt,
      caseCount: _integer(fields['caseCount']),
      firstCaseId: _resourceId(fields['firstCaseId']),
      lastCaseId: _resourceId(fields['lastCaseId']),
      status: _issueStatus(fields['status']),
      appVersion: _optionalText(fields['appVersion']),
      buildNumber: _optionalText(fields['buildNumber']),
      releaseChannel: _optionalText(fields['releaseChannel']),
    );
  }

  ArmCaseRecord? _caseRecord(firestore_api.Document document) {
    final fields = document.fields ?? const <String, firestore_api.Value>{};
    final caseId = _resourceId(fields['caseId']) ?? _documentId(document);
    final issueId = _resourceId(fields['issueId']);
    final createdAt = _timestamp(fields['createdAt']);
    if (caseId == null || issueId == null || createdAt == null) {
      return null;
    }
    return ArmCaseRecord(
      caseId: caseId,
      issueId: issueId,
      // The issue ID is derived from the capture fingerprint, so it is the
      // truthful stand-in when a legacy document omits the field.
      fingerprint: _text(fields['fingerprint'], fallback: issueId),
      severity: _text(fields['severity'], fallback: 'unknown'),
      category: _text(fields['category']),
      feature: _text(fields['feature']),
      operation: _text(fields['operation']),
      message: _text(fields['message']),
      errorType: _text(fields['errorType']),
      stackTrace: _text(fields['stackTrace']),
      sessionId: _text(fields['sessionId']),
      handled: fields['handled']?.booleanValue ?? false,
      createdAt: createdAt,
      context: _jsonMap(fields['context']),
      tags: _jsonMap(fields['tags']),
      breadcrumbs: _jsonMapList(fields['breadcrumbs']),
      errorName: _optionalText(fields['errorName']),
      errorData: _optionalJsonMap(fields['errorData']),
      recoverySnapshot: _optionalJsonMap(fields['recoverySnapshot']),
      screenshot: _optionalJsonMap(fields['screenshot']),
      status: _caseStatus(fields['status']),
      appVersion: _optionalText(fields['appVersion']),
      buildNumber: _optionalText(fields['buildNumber']),
      releaseChannel: _optionalText(fields['releaseChannel']),
    );
  }
}

class _Page<T> {
  const _Page({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;
}

_Page<T> _slice<T>({
  required List<T> records,
  required ArmPageCursor? cursor,
  required int pageSize,
  required DateTime Function(T) timestampOf,
  required String Function(T) idOf,
}) {
  var start = 0;
  if (cursor != null) {
    while (start < records.length) {
      final record = records[start];
      start += 1;
      if (idOf(record) == cursor.documentId &&
          timestampOf(record).isAtSameMomentAs(cursor.timestamp)) {
        break;
      }
    }
  }
  final remaining = start >= records.length
      ? <T>[]
      : records.sublist(start);
  final items = remaining.take(pageSize).toList(growable: false);
  return _Page<T>(items: items, hasMore: remaining.length > items.length);
}

int _compare(
  DateTime leftTimestamp,
  String leftId,
  DateTime rightTimestamp,
  String rightId,
) {
  final byTimestamp = leftTimestamp.compareTo(rightTimestamp);
  return byTimestamp != 0 ? byTimestamp : leftId.compareTo(rightId);
}

String _caseStatusWireName(ArmCaseStatus status) =>
    status == ArmCaseStatus.newCase ? 'new' : status.name;

String? _documentId(firestore_api.Document document) {
  final name = document.name;
  if (name == null) return null;
  final id = name.split('/').last;
  return _isResourceId(id) ? id : null;
}

bool _isResourceId(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value);

String? _resourceId(firestore_api.Value? value) {
  final text = value?.stringValue?.trim();
  if (text == null || !_isResourceId(text)) return null;
  return text;
}

String _text(firestore_api.Value? value, {String fallback = ''}) {
  final text = value?.stringValue;
  return text == null || text.isEmpty ? fallback : text;
}

String? _optionalText(firestore_api.Value? value) {
  final text = value?.stringValue;
  return text == null || text.isEmpty ? null : text;
}

int _integer(firestore_api.Value? value) {
  final raw = value?.integerValue;
  if (raw != null) return int.tryParse(raw) ?? 0;
  return value?.doubleValue?.toInt() ?? 0;
}

/// ARM writers have emitted both real Firestore timestamps and ISO-8601
/// strings, so both are accepted and normalised to UTC here.
DateTime? _timestamp(firestore_api.Value? value) {
  final raw = value?.timestampValue ?? value?.stringValue;
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed?.toUtc();
}

ArmIssueStatus? _issueStatus(firestore_api.Value? value) {
  final text = value?.stringValue?.trim().toLowerCase().replaceAll(' ', '_');
  if (text == null || text.isEmpty) return null;
  for (final status in ArmIssueStatus.values) {
    if (status.name == text) return status;
  }
  return null;
}

ArmCaseStatus? _caseStatus(firestore_api.Value? value) {
  final text = value?.stringValue?.trim().toLowerCase().replaceAll(' ', '_');
  if (text == null || text.isEmpty) return null;
  if (text == 'new') return ArmCaseStatus.newCase;
  for (final status in ArmCaseStatus.values) {
    if (status.name == text) return status;
  }
  return null;
}

Map<String, Object?> _jsonMap(firestore_api.Value? value) =>
    _optionalJsonMap(value) ?? const <String, Object?>{};

Map<String, Object?>? _optionalJsonMap(firestore_api.Value? value) {
  final fields = value?.mapValue?.fields;
  if (fields == null) return null;
  return <String, Object?>{
    for (final entry in fields.entries) entry.key: _jsonValue(entry.value),
  };
}

List<Map<String, Object?>> _jsonMapList(firestore_api.Value? value) {
  final values = value?.arrayValue?.values;
  if (values == null) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in values) _optionalJsonMap(item) ?? <String, Object?>{},
  ];
}

Object? _jsonValue(firestore_api.Value value) {
  if (value.nullValue != null) return null;
  if (value.booleanValue != null) return value.booleanValue;
  if (value.integerValue != null) {
    return int.tryParse(value.integerValue!) ?? value.integerValue;
  }
  if (value.doubleValue != null) return value.doubleValue;
  if (value.timestampValue != null) return value.timestampValue;
  if (value.stringValue != null) return value.stringValue;
  if (value.bytesValue != null) return value.bytesValue;
  if (value.referenceValue != null) return value.referenceValue;
  if (value.geoPointValue != null) {
    return <String, Object?>{
      'latitude': value.geoPointValue!.latitude,
      'longitude': value.geoPointValue!.longitude,
    };
  }
  if (value.arrayValue != null) {
    return <Object?>[
      for (final item in value.arrayValue!.values ?? const <firestore_api.Value>[])
        _jsonValue(item),
    ];
  }
  if (value.mapValue != null) {
    return <String, Object?>{
      for (final entry
          in (value.mapValue!.fields ?? const <String, firestore_api.Value>{})
              .entries)
        entry.key: _jsonValue(entry.value),
    };
  }
  return null;
}
