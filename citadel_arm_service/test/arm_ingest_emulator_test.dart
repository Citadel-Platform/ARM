@Tags(<String>['emulator'])
library;

import 'dart:io';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The ingest's writes, read back by the evidence service's own repository
/// through one real Firestore.
///
/// The two ends of ARM evidence are now two services: this one writes it and
/// `citadel-arm-evidence` reads it for the Console. Each has its own tests and
/// both could be green while disagreeing — a timestamp as a string one side
/// never parses, a count as a double — which is `G6-4`'s shape. Only a write
/// on one side and a read on the other catches that.
void main() {
  final String host = Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '';
  final String? skip = host.isEmpty
      ? 'Set FIRESTORE_EMULATOR_HOST to run this against the emulator.'
      : null;

  late firestore_api.FirestoreApi api;
  late ArmIngestService ingest;
  late FirestoreArmEvidenceRepository evidence;
  final String client = 'client-${DateTime.now().microsecondsSinceEpoch}';
  final DateTime now = DateTime.now().toUtc();

  setUp(() {
    api = firestore_api.FirestoreApi(_EmulatorAdminClient(), rootUrl: 'http://$host/');
    final _FixedRouter router = _FixedRouter();
    ingest = ArmIngestService(
      keys: const _Keys(),
      router: router,
      store: FirestoreArmIngestStore(firestoreApi: api),
      rateLimiter: ArmIngestRateLimiter(capturesPerMinute: 1000),
      clock: () => now,
    );
    evidence = FirestoreArmEvidenceRepository(
      firestoreApi: api,
      router: router,
      registryProjectId: _project,
    );
  });

  Map<String, Object?> capture(String id, String message, DateTime at) => <String, Object?>{
    'captureId': id,
    'occurredAt': at.toIso8601String(),
    'source': 'web',
    'severity': 'serious',
    'feature': 'checkout-$client',
    'operation': 'pay',
    'errorType': 'TypeError',
    'message': message,
    'stackTrace': 'TypeError: $message\n    at pay (https://x.example/app-3f9a1c.js:1:2)',
    'sessionId': 'session-1',
    'environment': 'production',
    'appVersion': at == now ? '2.0.0' : '1.9.0',
    'context': <String, Object?>{'route': '/checkout'},
    'breadcrumbs': <Object?>[
      <String, Object?>{
        'message': 'click button#pay',
        'level': 'info',
        'timestamp': at.toIso8601String(),
        'category': 'click',
      },
    ],
  };

  test('captures become an issue and cases the evidence service reads', skip: skip, () async {
    await ingest.accept(clientId: client, key: 'k', body: <Object?>[
      capture('a', 'Order 9817 failed', now),
      capture('b', 'Order 1042 failed', now),
    ]);

    final List<ArmIssueRecord> issues = (await evidence.listIssues(
      projectId: client,
      query: const ArmIssueQuery(pageSize: 100),
    )).issues.where((i) => i.feature == 'checkout-$client').toList();
    expect(issues, hasLength(1), reason: 'one fault, grouped');
    final ArmIssueRecord issue = issues.single;
    expect(issue.caseCount, 2);
    expect(issue.severity, 'serious');
    expect(issue.environment, 'production');
    expect(issue.lastSeenAt.isAtSameMomentAs(DateTime.parse(now.toIso8601String())), isTrue);

    final List<ArmCaseRecord> cases = (await evidence.listCases(
      projectId: client,
      query: ArmCaseQuery(issueId: issue.issueId, pageSize: 100),
    )).cases;
    expect(cases, hasLength(2));
    expect(cases.first.status, ArmCaseStatus.newCase);
    expect(cases.first.breadcrumbs.single['category'], 'click');
    expect(cases.first.context['route'], '/checkout');
    expect(cases.first.stackTrace, contains('app-3f9a1c.js'), reason: 'the stack as sent');
  });

  test('a redelivery records nothing new, triage survives, and a late capture '
      'does not move the issue backwards', skip: skip, () async {
    final String issueId = (await ingest.accept(clientId: client, key: 'k', body: <Object?>[
      capture('c', 'Order 7 failed', now),
    ])).single.issueId;

    final List<ArmIngestOutcome> again = await ingest.accept(
      clientId: client,
      key: 'k',
      body: <Object?>[capture('c', 'Order 7 failed', now)],
    );
    expect(again.single.duplicate, isTrue);

    await evidence.updateIssueStatus(
      projectId: client,
      issueId: issueId,
      mutation: const ArmIssueStatusMutation(
        status: ArmIssueStatus.investigating,
        updatedBy: 'operator@example.com',
      ),
    );

    // Sent as a page closed an hour ago, arriving now.
    await ingest.accept(clientId: client, key: 'k', body: <Object?>[
      capture('d', 'Order 8 failed', now.subtract(const Duration(hours: 1))),
    ]);

    final ArmIssueRecord issue = (await evidence.listIssues(
      projectId: client,
      query: const ArmIssueQuery(pageSize: 100),
    )).issues.singleWhere((i) => i.issueId == issueId);
    expect(issue.caseCount, 4, reason: 'a, b, c and d — the redelivery of c is not counted');
    expect(issue.status, ArmIssueStatus.investigating, reason: 'an operator\'s triage survives recurrence');
    expect(issue.appVersion, '2.0.0', reason: 'the latest occurrence\'s release, not the late one\'s');
    expect(issue.lastSeenAt.isBefore(now.subtract(const Duration(minutes: 30))), isFalse);
    expect(issue.firstSeenAt.isBefore(now), isTrue, reason: 'the late capture is the earliest');
  });
}

const String _project = 'demo-citadel-arm';

final class _Keys implements ArmIngestKeyRegistry {
  const _Keys();
  @override
  Future<bool> verify(String clientId, String key) async => key == 'k';
}

final class _FixedRouter implements ArmProjectRouter {
  @override
  Future<ArmProjectTarget> resolve(
    String projectId, {
    ArmRoutedOffering offering = ArmRoutedOffering.evidence,
  }) async => const ArmProjectTarget(
    projectId: _project,
    customerProjectId: _project,
    databaseId: '(default)',
  );
}

final class _EmulatorAdminClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}
