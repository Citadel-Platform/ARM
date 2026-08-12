import 'dart:convert';

import 'package:arm_tooling_server/arm_tooling_server.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _projectId = 'customer-project';

void main() {
  test('records a capture as timestamps, not sortable-by-accident strings', () async {
    final writes = <_Write>[];
    final sink = _sink(writes);

    await sink.record(_request());

    final caseWrite = writes.singleWhere((w) => w.path.contains('/armCases/'));
    final issueWrite = writes.singleWhere((w) => w.path.contains('/armIssues/'));

    for (final field in <String>['createdAt']) {
      expect(
        caseWrite.fields[field],
        contains('timestampValue'),
        reason: 'Firestore orders by value type before value, so a collection '
            'mixing timestamps and ISO strings cannot be ordered or paged',
      );
    }
    for (final field in <String>['firstSeenAt', 'lastSeenAt']) {
      expect(issueWrite.fields[field], contains('timestampValue'));
    }
  });

  test('stamps a new case as untriaged', () async {
    final writes = <_Write>[];

    await _sink(writes).record(_request());

    final caseWrite = writes.singleWhere((w) => w.path.contains('/armCases/'));
    expect(caseWrite.fields['status'], contains('new'));
    expect(caseWrite.fields['handled'], contains('true'));
  });

  test('never writes an issue field it does not own', () async {
    final writes = <_Write>[];

    await _sink(writes).record(_request());

    final issueWrite = writes.singleWhere((w) => w.path.contains('/armIssues/'));
    // Without a mask a patch replaces the whole document, silently erasing an
    // operator's triage every time the same issue recurred.
    expect(issueWrite.mask, isNotEmpty);
    expect(issueWrite.mask, isNot(contains('status')));
    expect(issueWrite.mask, isNot(contains('statusUpdatedBy')));
    expect(issueWrite.mask, isNot(contains('statusUpdatedAt')));
    expect(issueWrite.mask, containsAll(<String>['lastSeenAt', 'caseCount']));
  });

  test('preserves the first sighting across recurrences', () async {
    final writes = <_Write>[];
    final sink = _sink(
      writes,
      existingIssue: <String, Object?>{
        'fields': <String, Object?>{
          'firstSeenAt': <String, Object?>{
            'timestampValue': '2026-01-01T00:00:00.000Z',
          },
          'firstCaseId': <String, Object?>{'stringValue': 'ARM-20260101-AAAA'},
          'caseCount': <String, Object?>{'integerValue': '4'},
          'status': <String, Object?>{'stringValue': 'monitoring'},
        },
      },
    );

    await sink.record(_request());

    final issueWrite = writes.singleWhere((w) => w.path.contains('/armIssues/'));
    expect(issueWrite.fields['firstSeenAt'], contains('2026-01-01'));
    expect(issueWrite.fields['firstCaseId'], contains('ARM-20260101-AAAA'));
    expect(issueWrite.fields['caseCount'], contains('5'));
  });
}

FirestoreServiceAccountArmSink _sink(
  List<_Write> writes, {
  Map<String, Object?>? existingIssue,
}) {
  final client = MockClient((http.Request request) async {
    if (request.method == 'GET') {
      return existingIssue == null
          ? _json(<String, Object?>{
              'error': <String, Object?>{'code': 404},
            }, 404)
          : _json(existingIssue, 200);
    }
    final decoded = jsonDecode(request.body) as Map<String, Object?>;
    final fields = (decoded['fields'] as Map<String, Object?>).map(
      (key, value) => MapEntry(key, jsonEncode(value)),
    );
    writes.add(
      _Write(
        path: Uri.decodeFull(request.url.path),
        fields: fields,
        mask: request.url.queryParametersAll['updateMask.fieldPaths'] ??
            const <String>[],
      ),
    );
    return _json(decoded, 200);
  });

  return FirestoreServiceAccountArmSink.withFirestoreApi(
    projectId: _projectId,
    firestoreApi: firestore_api.FirestoreApi(client),
  );
}

ArmCaptureRequest _request() => ArmCaptureRequest(
  severity: ArmSeverity.serious,
  category: 'runtime',
  feature: 'invoicing',
  operation: 'send_invoice_email',
  message: 'SMTP refused',
  errorType: 'SmtpException',
  stackTrace: 'stack',
  fingerprint: 'fingerprint-1',
  sessionId: 'session-1',
  breadcrumbs: const <ArmBreadcrumb>[],
  context: <String, dynamic>{},
  tags: <String, dynamic>{},
  handled: true,
);

http.Response _json(Map<String, Object?> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

class _Write {
  const _Write({
    required this.path,
    required this.fields,
    required this.mask,
  });

  final String path;
  final Map<String, String> fields;
  final List<String> mask;
}
