import 'dart:convert';

import 'package:googleapis/firestore/v1.dart' as firestore_api;

import 'arm_private_service.dart';
import 'arm_service_json.dart';
import 'arm_project_router.dart';
import 'arm_service_models.dart';

const String armIssuesCollectionId = 'armIssues';
const String armCasesCollectionId = 'armCases';

/// Where a project's support tickets live.
///
/// In the client's own boundary, beside the cases they point at: a ticket is
/// the client's conversation with their own customer, about their own fault.
/// The allowlist on it is enforced by this service on every read, never by
/// where the document sits.
const String armTicketsCollectionId = 'armTickets';

/// Where a project's alerting policies and channels live.
///
/// In the registry project rather than the client's, because it decides who
/// Citadel sends messages to.
const String armAlertingCollectionId = 'armAlerting';

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
    required String registryProjectId,
    String registryDatabaseId = '(default)',
    this.maxScanDocuments = armDefaultMaxScanDocuments,
    DateTime Function()? clock,
  }) : _firestoreApi = firestoreApi,
       _router = router,
       _registryDocumentsRoot =
           'projects/$registryProjectId/databases/$registryDatabaseId/documents',
       _clock = clock ?? (() => DateTime.now().toUtc());

  /// Where alerting configuration lives — the registry, never the client's
  /// own database. A client-writable document deciding who Citadel messages
  /// is a way to make Citadel send to anyone.
  final String _registryDocumentsRoot;

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

  @override
  Future<ArmCaseRecord?> updateCaseSeverity({
    required String projectId,
    required String caseId,
    required ArmCaseSeverityMutation mutation,
  }) async {
    final target = await _router.resolve(projectId);
    final name = '${target.documentsRoot}/$armCasesCollectionId/$caseId';
    // Written to `operatorSeverity`, never to `severity`. The captured value
    // is evidence about what the SDK saw; overwriting it would destroy the
    // only record of what the fault looked like when it happened.
    final updated = await _patchStatus(
      name: name,
      fields: <String, firestore_api.Value>{
        'operatorSeverity': firestore_api.Value(
          stringValue: armSeverityWireName(mutation.severity),
        ),
        'severityUpdatedAt': firestore_api.Value(
          timestampValue: _clock().toIso8601String(),
        ),
        'severityUpdatedBy': firestore_api.Value(
          stringValue: mutation.updatedBy,
        ),
        'severitySource': firestore_api.Value(
          stringValue: mutation.severitySource,
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

  @override
  Future<ArmIssueRecord?> updateIssueTags({
    required String projectId,
    required String issueId,
    required ArmIssueTagsMutation mutation,
  }) async {
    final target = await _router.resolve(projectId);
    final name = '${target.documentsRoot}/$armIssuesCollectionId/$issueId';
    // The whole array, replaced. Firestore has array-union, and using it here
    // would make a removal impossible to express through the same route.
    final updated = await _patchStatus(
      name: name,
      fields: <String, firestore_api.Value>{
        'tags': firestore_api.Value(
          arrayValue: firestore_api.ArrayValue(
            values: <firestore_api.Value>[
              for (final String tag in mutation.tags)
                firestore_api.Value(stringValue: tag),
            ],
          ),
        ),
        'tagsUpdatedAt': firestore_api.Value(
          timestampValue: _clock().toIso8601String(),
        ),
        'tagsUpdatedBy': firestore_api.Value(stringValue: mutation.updatedBy),
        'tagSource': firestore_api.Value(stringValue: mutation.tagSource),
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
  Future<ArmTicketPageSlice> listTickets({
    required String projectId,
    required ArmTicketQuery query,
  }) async {
    final target = await _router.resolve(projectId);
    final documents = await _scanCollection(target, armTicketsCollectionId);
    final records = <ArmTicketRecord>[];
    for (final document in documents) {
      final record = _ticketRecord(document);
      if (record == null) continue;
      if (query.status != null && record.status != query.status) continue;
      if (query.issueId != null && record.issueId != query.issueId) continue;
      records.add(record);
    }
    records.sort(
      (left, right) => _compare(
        right.updatedAt,
        right.ticketId,
        left.updatedAt,
        left.ticketId,
      ),
    );
    final page = _slice<ArmTicketRecord>(
      records: records,
      cursor: query.cursor,
      pageSize: query.pageSize,
      timestampOf: (record) => record.updatedAt,
      idOf: (record) => record.ticketId,
    );
    return ArmTicketPageSlice(tickets: page.items, hasMore: page.hasMore);
  }

  @override
  Future<ArmTicketRecord?> getTicket({
    required String projectId,
    required String ticketId,
  }) async {
    final target = await _router.resolve(projectId);
    final document = await _getDocument(
      '${target.documentsRoot}/$armTicketsCollectionId/$ticketId',
    );
    if (document == null) return null;
    final record = _ticketRecord(document);
    if (record == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'The stored ARM ticket is not readable.',
      );
    }
    return record;
  }

  @override
  Future<ArmTicketRecord> writeTicket({
    required String projectId,
    required ArmTicketRecord ticket,
  }) async {
    final target = await _router.resolve(projectId);
    // Round-tripped through the codec before it is written, so a shape the
    // reader would refuse can never reach storage.
    final String payload = jsonEncode(
      encodeArmTicketRecord(
        decodeArmTicketRecord(encodeArmTicketRecord(ticket), r'$'),
      ),
    );
    final name =
        '${target.documentsRoot}/$armTicketsCollectionId/${ticket.ticketId}';
    try {
      await _firestoreApi.projects.databases.documents.patch(
        firestore_api.Document(
          name: name,
          fields: <String, firestore_api.Value>{
            'ticketId': firestore_api.Value(stringValue: ticket.ticketId),
            // The whole ticket, as one payload. Its history is the document,
            // and a partial write of a history is a history with a hole in it.
            'ticket': firestore_api.Value(stringValue: payload),
            // Duplicated out of the payload so a listing can be ordered and a
            // status filtered without decoding every ticket in the project.
            'status': firestore_api.Value(stringValue: ticket.status.name),
            'updatedAt': firestore_api.Value(
              timestampValue: ticket.updatedAt.toUtc().toIso8601String(),
            ),
          },
        ),
        name,
        updateMask_fieldPaths: const <String>[
          'ticketId',
          'ticket',
          'status',
          'updatedAt',
        ],
      );
    } on firestore_api.DetailedApiRequestError catch (error) {
      throw _upstreamFailure(error);
    }
    return ticket;
  }

  ArmTicketRecord? _ticketRecord(firestore_api.Document document) {
    final fields = document.fields ?? const <String, firestore_api.Value>{};
    final String? payload = fields['ticket']?.stringValue;
    if (payload == null || payload.isEmpty) return null;
    try {
      return decodeArmTicketRecord(jsonDecode(payload), r'$');
    } on Object {
      // One unreadable ticket does not take the listing down with it: the rest
      // of the project's tickets are still answerable, and a page that failed
      // outright would hide them behind one bad document.
      return null;
    }
  }

  /// A project's alerting configuration, as one document.
  ///
  /// One document rather than two collections, because policies name channels
  /// by id and are edited together: a read that returned policies without the
  /// channels they reference would render a policy notifying nothing.
  ///
  /// **In the registry project, not the client's.** A notification channel
  /// holds the addresses Citadel will send to, and a policy decides when. A
  /// client-writable document deciding who Citadel messages is a way to make
  /// Citadel send to anyone.
  @override
  Future<ArmAlertingConfiguration> readAlerting({
    required String projectId,
  }) async {
    final name = '$_registryDocumentsRoot/$armAlertingCollectionId/$projectId';
    firestore_api.Document? document;
    try {
      document = await _firestoreApi.projects.databases.documents.get(name);
    } on firestore_api.DetailedApiRequestError catch (error) {
      // A project that has configured nothing has no document, which is an
      // empty configuration and not a failure.
      if (error.status != 404) rethrow;
    }
    if (document == null) {
      return ArmAlertingConfiguration(projectId: projectId);
    }
    final fields = document.fields ?? const <String, firestore_api.Value>{};
    final String? payload = fields['configuration']?.stringValue;
    if (payload == null || payload.isEmpty) {
      return ArmAlertingConfiguration(projectId: projectId);
    }
    try {
      return decodeArmAlertingConfiguration(jsonDecode(payload));
    } on Object {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'The stored ARM alerting configuration is not readable.',
      );
    }
  }

  @override
  Future<ArmAlertingConfiguration> writeAlerting({
    required String projectId,
    required ArmAlertingConfiguration configuration,
    required String updatedBy,
  }) async {
    final stored = configuration.copyWith(projectId: projectId);
    // Round-tripped through the codec before it is written, so a shape the
    // reader would refuse can never reach storage.
    final String payload = jsonEncode(
      encodeArmAlertingConfiguration(
        decodeArmAlertingConfiguration(
          encodeArmAlertingConfiguration(stored),
        ),
      ),
    );
    final name = '$_registryDocumentsRoot/$armAlertingCollectionId/$projectId';
    await _firestoreApi.projects.databases.documents.patch(
      firestore_api.Document(
        name: name,
        fields: <String, firestore_api.Value>{
          'projectId': firestore_api.Value(stringValue: projectId),
          'configuration': firestore_api.Value(stringValue: payload),
          'updatedAt': firestore_api.Value(
            timestampValue: _clock().toIso8601String(),
          ),
          'updatedBy': firestore_api.Value(stringValue: updatedBy),
        },
      ),
      name,
      updateMask_fieldPaths: const <String>[
        'projectId',
        'configuration',
        'updatedAt',
        'updatedBy',
      ],
    );
    return stored;
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
      tags: _tagList(fields['tags']),
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
      operatorSeverity: _optionalText(fields['operatorSeverity']),
      severityUpdatedBy: _optionalText(fields['severityUpdatedBy']),
      severityUpdatedAt: _timestamp(fields['severityUpdatedAt']),
    );
  }

  /// A fingerprint's tags, from whatever is stored.
  ///
  /// Tolerant of a missing or wrongly typed field and strict about the values:
  /// a document written by an older build has no `tags`, which is untagged and
  /// not an error, while a malformed entry is dropped rather than surfaced —
  /// a tag nobody can read is not worth failing a whole listing over.
  List<String> _tagList(firestore_api.Value? value) {
    final List<firestore_api.Value>? values = value?.arrayValue?.values;
    if (values == null) return const <String>[];
    final Set<String> tags = <String>{};
    for (final firestore_api.Value entry in values) {
      final String? tag = entry.stringValue?.trim().toLowerCase();
      if (tag == null || tag.isEmpty) continue;
      tags.add(tag);
    }
    final List<String> ordered = tags.toList()..sort();
    return List<String>.unmodifiable(ordered);
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
