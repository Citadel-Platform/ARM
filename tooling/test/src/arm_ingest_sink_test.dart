import 'dart:convert';

import 'package:arm_tooling/arm_tooling.dart';
import 'package:citadel_arm_service/citadel_arm_service.dart' as service;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' as shelf;

/// The Flutter SDK's senders, against the real ARM ingest handler in-process:
/// what the SDK sends is parsed by exactly the code the deployed ingest runs,
/// so the two cannot disagree about a field and both stay green.
void main() {
  late _Store store;
  late shelf.Handler ingest;

  setUp(() {
    store = _Store();
    ingest = service.createArmIngestHandler(
      service: service.ArmIngestService(
        keys: const _Keys(),
        router: const _Router(),
        store: store,
        rateLimiter: service.ArmIngestRateLimiter(capturesPerMinute: 100),
      ),
    );
  });

  ArmIngestConnection connection({String key = 'key-a'}) => ArmIngestConnection(
    clientId: 'client-a',
    ingestKey: key,
    ingestUrl: 'https://ingest.example/',
    httpClient: MockClient((http.Request request) async {
      final shelf.Response response = await ingest(
        shelf.Request(
          request.method,
          request.url,
          headers: request.headers,
          body: request.bodyBytes,
        ),
      );
      return http.Response(
        await response.readAsString(),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );

  ArmCaptureRequest request({ArmSeverity severity = ArmSeverity.serious}) =>
      ArmCaptureRequest(
        severity: severity,
        category: 'runtime',
        feature: 'checkout',
        operation: 'submit_payment',
        message: 'Payment failed for order 9817',
        errorType: 'StateError',
        stackTrace: '#0 submitPayment (package:app/checkout.dart:10:2)',
        fingerprint: 'fp',
        sessionId: 'session-1',
        breadcrumbs: <ArmBreadcrumb>[
          ArmBreadcrumb(
            message: 'tap Pay',
            level: 'info',
            timestamp: DateTime.utc(2026, 9, 23),
            category: 'ui',
          ),
        ],
        context: const <String, dynamic>{'route': '/checkout'},
        tags: const <String, dynamic>{},
        recoverySnapshot: const <String, dynamic>{'cartItems': 3},
        appVersion: '2.1.0',
        environment: 'production',
        handled: false,
      );

  test('a capture is accepted by the real ingest, and the case it made is returned', () async {
    final ArmCaptureResult result = await IngestArmSink(connection()).record(request());
    expect(result.caseId, matches(RegExp(r'^ARM-\d{8}-[0-9A-F]{8}$')));
    expect(result.issueId, startsWith('issue_'));
    expect(result.caseIdExposed, isTrue);
    final service.ArmIngestCapture stored = store.captures.single;
    expect(stored.source, service.ArmCaptureSource.flutter);
    expect(stored.feature, 'checkout');
    expect(stored.recoverySnapshot, <String, Object?>{'cartItems': 3});
    expect(stored.breadcrumbs.single.message, 'tap Pay');
    expect(stored.environment, 'production');
    expect(stored.handled, isFalse);
  });

  test('a refused key surfaces as the ingest said it', () async {
    await expectLater(
      IngestArmSink(connection(key: 'wrong')).record(request()),
      throwsA(
        isA<ArmIngestSendException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', contains('do not match')),
      ),
    );
  });

  test('a ticket opens in the Helpdesk through the ingest', () async {
    final String ticketId = await IngestArmTicketSink(connection()).open(
      const ArmTicketRequest(
        title: 'Cannot pay',
        description: 'The button spins.',
        contact: 'amy@example.sg',
        caseId: 'ARM-20260923-ABCDEF12',
        sessionId: 'session-1',
      ),
    );
    expect(ticketId, startsWith('ticket_'));
    final service.ArmTicketRecord ticket = store.tickets.single;
    expect(ticket.ticketId, ticketId);
    expect(ticket.reporterContact, 'amy@example.sg');
    expect(ticket.caseIds, <String>['ARM-20260923-ABCDEF12']);
    expect(store.ticketDatabase, 'citadel-manifold');
  });

  test('the capture shape carries what the Firestore sink used to write', () {
    final Map<String, Object?> json = armIngestCaptureJson(
      request(),
      captureId: 'abc',
      occurredAt: DateTime.utc(2026, 9, 23),
    );
    expect(jsonDecode(jsonEncode(json)), containsPair('source', 'flutter'));
    expect(json['occurredAt'], '2026-09-23T00:00:00.000Z');
    expect(json.containsKey('screenshot'), isFalse);
  });
}

final class _Keys implements service.ArmIngestKeyRegistry {
  const _Keys();
  @override
  Future<bool> verify(String clientId, String key) async =>
      clientId == 'client-a' && key == 'key-a';
}

final class _Router implements service.ArmProjectRouter {
  const _Router();
  @override
  Future<service.ArmProjectTarget> resolve(
    String projectId, {
    service.ArmRoutedOffering offering = service.ArmRoutedOffering.evidence,
  }) async => service.ArmProjectTarget(
    projectId: projectId,
    customerProjectId: 'customer-project',
    databaseId: offering.databaseId,
  );
}

final class _Store implements service.ArmIngestStore {
  final List<service.ArmIngestCapture> captures = <service.ArmIngestCapture>[];
  final List<service.ArmTicketRecord> tickets = <service.ArmTicketRecord>[];
  String? ticketDatabase;

  @override
  Future<service.ArmIngestOutcome> record({
    required service.ArmProjectTarget target,
    required String caseId,
    required service.ArmIngestCapture capture,
    required ArmCaptureRequest request,
    required DateTime receivedAt,
  }) async {
    captures.add(capture);
    return service.ArmIngestOutcome(
      captureId: capture.captureId,
      caseId: caseId,
      issueId: buildArmIssueId(request.fingerprint),
      duplicate: false,
    );
  }

  @override
  Future<bool> openTicket({
    required service.ArmProjectTarget target,
    required service.ArmTicketRecord ticket,
  }) async {
    ticketDatabase = target.databaseId;
    tickets.add(ticket);
    return false;
  }
}
