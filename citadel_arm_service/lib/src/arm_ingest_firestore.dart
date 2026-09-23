import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:crypto/crypto.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;

import 'arm_ingest.dart';
import 'arm_private_service.dart';
import 'arm_project_router.dart';
import 'arm_service_models.dart' show ArmServiceErrorCode;

/// Where a client's ARM ingest key is kept: `arm_projects/{projectId}` in the
/// registry, field `ingestKey`.
///
/// The registry rules' catch-all closes the collection to every browser, the
/// Console included, for the reason Conduit's `conduit_projects` is closed: a
/// reader learns the key, a writer can mint one. The Platform API issues it,
/// under its own account; this service only reads it.
const String armProjectsCollectionId = 'arm_projects';

final class FirestoreArmIngestKeyRegistry implements ArmIngestKeyRegistry {
  FirestoreArmIngestKeyRegistry({
    required firestore_api.FirestoreApi firestoreApi,
    required String registryProjectId,
    String registryDatabaseId = '(default)',
    this.cacheDuration = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _firestoreApi = firestoreApi,
       _documentsRoot =
           'projects/$registryProjectId/databases/$registryDatabaseId/documents',
       _clock = clock ?? (() => DateTime.now().toUtc());

  final firestore_api.FirestoreApi _firestoreApi;
  final String _documentsRoot;
  final Duration cacheDuration;
  final DateTime Function() _clock;
  final Map<String, ({String? key, DateTime expiresAt})> _cache =
      <String, ({String? key, DateTime expiresAt})>{};

  @override
  Future<bool> verify(String clientId, String key) async {
    final DateTime now = _clock();
    final cached = _cache[clientId];
    String? held;
    if (cached != null && cached.expiresAt.isAfter(now)) {
      held = cached.key;
    } else {
      // A direct read of one document, never a scan of every client's: the
      // client id names it.
      try {
        final firestore_api.Document document = await _firestoreApi
            .projects
            .databases
            .documents
            .get('$_documentsRoot/$armProjectsCollectionId/$clientId');
        final String? value = document.fields?['ingestKey']?.stringValue?.trim();
        held = value == null || value.isEmpty ? null : value;
      } on firestore_api.DetailedApiRequestError catch (error) {
        if (error.status != 404) {
          throw const ArmServiceException(
            code: ArmServiceErrorCode.unavailable,
            message: 'The Citadel registry is unavailable.',
            retryable: true,
          );
        }
        held = null;
      }
      // Cached for a minute either way. A rotated key therefore takes up to a
      // minute to stop working, which is the price of not reading the registry
      // on every capture.
      _cache[clientId] = (key: held, expiresAt: now.add(cacheDuration));
    }
    return held != null && _constantTimeEquals(held, key);
  }
}

/// Compares digests rather than strings, so the time taken says nothing about
/// how much of a guessed key was right.
bool _constantTimeEquals(String a, String b) {
  final List<int> left = sha256.convert(a.codeUnits).bytes;
  final List<int> right = sha256.convert(b.codeUnits).bytes;
  var difference = 0;
  for (var i = 0; i < left.length; i += 1) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

/// Writes a capture into the client's `citadel-arm` in one transaction.
///
/// The issue upsert is `tooling_core`'s, done here instead of in a browser:
/// read the issue, keep its first-seen time and first case, add one to
/// `caseCount`, and write back **only the capture-owned fields** through an
/// update mask, so an operator's triage — `status`, tags — survives every
/// recurrence. The case is created with `exists: false`, so a redelivered
/// capture finds its case already there and changes nothing.
final class FirestoreArmIngestStore implements ArmIngestStore {
  FirestoreArmIngestStore({
    required firestore_api.FirestoreApi firestoreApi,
    this.maxAttempts = 4,
  }) : _firestoreApi = firestoreApi;

  final firestore_api.FirestoreApi _firestoreApi;
  final int maxAttempts;

  @override
  Future<ArmIngestOutcome> record({
    required ArmProjectTarget target,
    required String caseId,
    required ArmIngestCapture capture,
    required ArmCaptureRequest request,
    required DateTime receivedAt,
  }) async {
    final String database =
        'projects/${target.customerProjectId}/databases/${target.databaseId}';
    final String issueId = buildArmIssueId(request.fingerprint);
    final String issueName = '${target.documentsRoot}/armIssues/$issueId';
    final String caseName = '${target.documentsRoot}/armCases/$caseId';
    final documents = _firestoreApi.projects.databases.documents;

    for (var attempt = 1; ; attempt += 1) {
      try {
        final String transaction = (await documents.beginTransaction(
          firestore_api.BeginTransactionRequest(),
          database,
        )).transaction!;
        final List<firestore_api.BatchGetDocumentsResponseElement> read =
            await documents.batchGet(
              firestore_api.BatchGetDocumentsRequest(
                documents: <String>[issueName, caseName],
                transaction: transaction,
              ),
              database,
            );
        firestore_api.Document? found(String name) => read
            .map((element) => element.found)
            .whereType<firestore_api.Document>()
            .where((document) => document.name == name)
            .firstOrNull;

        if (found(caseName) != null) {
          await documents.rollback(
            firestore_api.RollbackRequest(transaction: transaction),
            database,
          );
          return ArmIngestOutcome(
            captureId: capture.captureId,
            caseId: caseId,
            issueId: issueId,
            duplicate: true,
          );
        }

        final Map<String, firestore_api.Value> existing =
            found(issueName)?.fields ?? const <String, firestore_api.Value>{};
        final int count = int.tryParse(existing['caseCount']?.integerValue ?? '') ??
            existing['caseCount']?.doubleValue?.toInt() ??
            0;
        // A beacon can arrive after a later capture of the same fault did —
        // it was sent as the page closed, or buffered offline. The issue's
        // latest occurrence and first occurrence are kept as the extremes,
        // never simply overwritten by whichever capture arrived last.
        final DateTime? seenBefore = DateTime.tryParse(
          existing['lastSeenAt']?.timestampValue ?? '',
        )?.toUtc();
        final DateTime? firstBefore = DateTime.tryParse(
          existing['firstSeenAt']?.timestampValue ?? '',
        )?.toUtc();
        final bool isLatest =
            seenBefore == null || !capture.occurredAt.isBefore(seenBefore);
        final bool isFirst =
            firstBefore == null || capture.occurredAt.isBefore(firstBefore);
        final Map<String, dynamic> issue = buildArmIssueDocumentMap(
          issueId: issueId,
          caseId: caseId,
          request: request,
          firstSeenAt: isFirst ? capture.occurredAt : firstBefore,
          lastSeenAt: isLatest ? capture.occurredAt : seenBefore,
          firstCaseId: isFirst
              ? caseId
              : existing['firstCaseId']?.stringValue ?? caseId,
          caseCount: count + 1,
        );
        if (!isLatest) {
          // The release and environment on an issue describe its latest
          // occurrence; an older capture does not get to overwrite them.
          issue['lastCaseId'] = existing['lastCaseId']?.stringValue ?? caseId;
          for (final String field in const <String>[
            'appVersion',
            'buildNumber',
            'releaseChannel',
            'environment',
            'severity',
          ]) {
            issue.remove(field);
          }
        }
        final Map<String, dynamic> caseDocument = <String, dynamic>{
          ...buildArmCaseDocumentMap(
            caseId: caseId,
            issueId: issueId,
            request: request,
            createdAt: capture.occurredAt,
          ),
          // Which kind of client sent it, and when Citadel received it. The
          // reader ignores both; an operator chasing a clock-skewed browser
          // does not.
          'source': capture.source.name,
          'receivedAt': receivedAt,
        };

        await documents.commit(
          firestore_api.CommitRequest(
            transaction: transaction,
            writes: <firestore_api.Write>[
              firestore_api.Write(
                update: firestore_api.Document(
                  name: caseName,
                  fields: encodeArmFields(caseDocument),
                ),
                currentDocument: firestore_api.Precondition(exists: false),
              ),
              firestore_api.Write(
                update: firestore_api.Document(
                  name: issueName,
                  fields: encodeArmFields(issue),
                ),
                updateMask: firestore_api.DocumentMask(
                  fieldPaths: issue.keys.map(_fieldPath).toList(),
                ),
              ),
            ],
          ),
          database,
        );
        return ArmIngestOutcome(
          captureId: capture.captureId,
          caseId: caseId,
          issueId: issueId,
          duplicate: false,
        );
      } on firestore_api.DetailedApiRequestError catch (error) {
        // Two captures of one fault racing on its issue. Firestore aborts one;
        // it goes again from the read.
        if (error.status == 409 && attempt < maxAttempts) continue;
        throw _failure(error);
      }
    }
  }

  ArmServiceException _failure(firestore_api.DetailedApiRequestError error) {
    // No database, or no grant on it: the client's setup is unfinished, which
    // is the operator's to fix and not the caller's. Same reading as the
    // evidence service's (F-024, `G4-64`).
    if (error.status == 404 || error.status == 403 || error.status == 401) {
      return const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message:
            'ARM is not set up to receive evidence for this client yet. The '
            'operator finishes this in the Console: ARM → Set up ARM.',
      );
    }
    return const ArmServiceException(
      code: ArmServiceErrorCode.unavailable,
      message: 'The client\'s ARM database is unavailable. Retry later.',
      retryable: true,
    );
  }
}

/// A field name as an update-mask path. Plain identifiers go bare; anything
/// else is backquoted, as Firestore requires.
String _fieldPath(String name) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name) ? name : '`$name`';

/// Dart values as Firestore fields, the types the evidence service reads back:
/// `DateTime` as a timestamp, whole numbers as integers.
Map<String, firestore_api.Value> encodeArmFields(Map<String, dynamic> map) =>
    <String, firestore_api.Value>{
      for (final MapEntry<String, dynamic> entry in map.entries)
        entry.key: encodeArmValue(entry.value),
    };

firestore_api.Value encodeArmValue(Object? value) {
  if (value is firestore_api.Value) return value;
  if (value == null) return firestore_api.Value(nullValue: 'NULL_VALUE');
  if (value is bool) return firestore_api.Value(booleanValue: value);
  if (value is int) return firestore_api.Value(integerValue: '$value');
  if (value is double) return firestore_api.Value(doubleValue: value);
  if (value is DateTime) {
    return firestore_api.Value(timestampValue: value.toUtc().toIso8601String());
  }
  if (value is String) return firestore_api.Value(stringValue: value);
  if (value is Map) {
    return firestore_api.Value(
      mapValue: firestore_api.MapValue(
        fields: encodeArmFields(Map<String, dynamic>.from(value)),
      ),
    );
  }
  if (value is Iterable) {
    return firestore_api.Value(
      arrayValue: firestore_api.ArrayValue(
        values: value.map(encodeArmValue).toList(),
      ),
    );
  }
  return firestore_api.Value(stringValue: value.toString());
}
