import 'dart:convert';
import 'dart:io';

import 'package:arm_tooling_core/arm_tooling_core.dart' show ArmCaptureRequest;
import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// OpenTelemetry into ARM (Feature 1.6.4), against exports recorded from the
/// official OpenTelemetry JS SDK — see `fixtures/otlp/README.md`.
void main() {
  List<int> fixture(String name) => File('test/fixtures/otlp/$name').readAsBytesSync();

  List<Map<String, Object?>> convert(String name) => armCapturesFromOtlp(
    signal: name.startsWith('traces') ? ArmOtlpSignal.traces : ArmOtlpSignal.logs,
    body: fixture(name),
    protobuf: name.endsWith('.pb'),
  );

  for (final String encoding in <String>['pb', 'json']) {
    group('recorded $encoding export', () {
      test('a span with a recorded exception is one capture, typed by the exception', () {
        final List<Map<String, Object?>> captures = convert('traces-1.$encoding');
        expect(captures, hasLength(1), reason: 'the ERROR status is the same fault, not a second one');
        final Map<String, Object?> c = captures.single;
        expect(c['source'], 'otlp');
        expect(c['errorType'], 'CardDeclined');
        expect(c['message'], 'Card declined for invoice 881');
        expect(c['stackTrace'], contains('billing/gateway.py'));
        expect(c['feature'], 'billing-worker');
        expect(c['operation'], 'POST /invoices/{id}/charge');
        expect(c['appVersion'], '3.2.1');
        expect(c['environment'], 'e2e');
        final Map<String, Object?> context = c['context']! as Map<String, Object?>;
        expect(context['runtime'], 'CPython 3.12.4');
        expect(context['request'], <String, Object?>{
          'method': 'POST',
          'route': '/invoices/{id}/charge',
          'path': '/invoices/881/charge',
          'status': 500,
          'durationMs': isA<int>(),
        });
        expect(c['sessionId'], matches(RegExp(r'^[0-9a-f]{32}$')), reason: 'the trace id');
        // Valid for the ingest's own parser.
        expect(parseArmIngestBatch(captures), hasLength(1));
      });

      test('a healthy span is acknowledged and dropped', () {
        expect(convert('traces-2.$encoding'), isEmpty);
      });

      test('an ERROR span with no exception is a SpanError', () {
        final Map<String, Object?> c = convert('traces-3.$encoding').single;
        expect(c['errorType'], 'SpanError');
        expect(c['message'], 'Reconciliation left 3 rows unmatched');
        expect(c['operation'], 'nightly-reconcile');
      });

      test('logs below ERROR are dropped; ERROR and FATAL become captures', () {
        expect(convert('logs-1.$encoding'), isEmpty);
        final Map<String, Object?> error = convert('logs-2.$encoding').single;
        expect(error['errorType'], 'LogError');
        expect(error['message'], 'Ledger export failed: disk full');
        expect(error['operation'], 'export_ledger');
        expect(error['severity'], 'serious');
        final Map<String, Object?> fatal = convert('logs-3.$encoding').single;
        expect(fatal['errorType'], 'MemoryError');
        expect(fatal['message'], 'out of memory');
        expect(fatal['severity'], 'critical');
        expect(fatal['stackTrace'], contains('worker.py'));
      });
    });
  }

  test('protobuf and JSON exports of the same thing become the same captures', () {
    for (final String name in <String>['traces-1', 'traces-3', 'logs-2', 'logs-3']) {
      final Map<String, Object?> pb = convert('$name.pb').single;
      final Map<String, Object?> json = convert('$name.json').single;
      for (final String field in <String>['errorType', 'message', 'feature', 'operation', 'severity', 'stackTrace', 'appVersion', 'environment']) {
        expect(pb[field], json[field], reason: '$name $field');
      }
    }
  });

  test('a redelivered export yields the same capture ids', () {
    expect(convert('traces-1.pb').single['captureId'], convert('traces-1.pb').single['captureId']);
  });

  test('a body that is not an export is a 400', () {
    expect(
      () => armCapturesFromOtlp(signal: ArmOtlpSignal.traces, body: <int>[0xff, 0xff, 0xff], protobuf: true),
      throwsA(isA<ArmIngestRejection>().having((r) => r.status, 'status', 400)),
    );
    expect(
      () => armCapturesFromOtlp(signal: ArmOtlpSignal.logs, body: utf8.encode('[1]'), protobuf: false),
      throwsA(isA<ArmIngestRejection>().having((r) => r.status, 'status', 400)),
    );
  });

  test('a Python fault survives its line number moving', () {
    Map<String, Object?> capture(int line) => <String, Object?>{
      'captureId': 'c$line',
      'occurredAt': DateTime.utc(2026, 9, 23).toIso8601String(),
      'source': 'otlp',
      'feature': 'billing-worker',
      'operation': 'charge',
      'errorType': 'CardDeclined',
      'message': 'Card declined for invoice $line',
      'sessionId': 's',
      'stackTrace': 'Traceback (most recent call last):\n  File "billing/charge.py", line $line, in charge\n'
          '    at Order.pay(Order.java:$line)\n    main.go:$line +0x1f\n'
          'billing.gateway.CardDeclined: Card declined for invoice $line',
    };
    final List<ArmIngestCapture> parsed = parseArmIngestBatch(<Object?>[capture(40), capture(47)], now: DateTime.utc(2026, 9, 23));
    expect(armCaptureRequestFor(parsed[0]).fingerprint, armCaptureRequestFor(parsed[1]).fingerprint);
  });

  group('the routes', () {
    late _Store store;
    late Handler handler;
    setUp(() {
      store = _Store();
      handler = createArmIngestHandler(
        service: ArmIngestService(
          keys: const _Keys(),
          router: const _Router(),
          store: store,
          rateLimiter: ArmIngestRateLimiter(capturesPerMinute: 100),
        ),
      );
    });

    Request post(String path, List<int> body, {String type = 'application/x-protobuf', bool gzipped = false, String key = 'key-a'}) => Request(
      'POST',
      Uri.parse('http://x$path'),
      headers: <String, String>{
        'content-type': type,
        'x-citadel-client': 'client-a',
        'x-arm-key': key,
        if (gzipped) 'content-encoding': 'gzip',
      },
      body: gzipped ? gzip.encode(body) : body,
    );

    test('protobuf in, an empty protobuf success out, the capture recorded', () async {
      final Response r = await handler(post('/v1/traces', fixture('traces-1.pb')));
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'application/x-protobuf');
      expect(await r.read().expand((c) => c).toList(), isEmpty);
      expect(store.captures.single.source, ArmCaptureSource.otlp);
    });

    test('gzipped JSON logs', () async {
      final Response r = await handler(post('/v1/logs', fixture('logs-3.json'), type: 'application/json', gzipped: true));
      expect(r.statusCode, 200);
      expect(await r.readAsString(), '{}');
      expect(store.captures.single.errorType, 'MemoryError');
    });

    test('a quiet export still has its key checked', () async {
      expect((await handler(post('/v1/traces', fixture('traces-2.pb')))).statusCode, 200);
      expect((await handler(post('/v1/traces', fixture('traces-2.pb'), key: 'wrong'))).statusCode, 401);
      expect(store.captures, isEmpty);
    });

    test('an exporter is allowed its content-encoding header by CORS', () async {
      final Response r = await handler(Request('OPTIONS', Uri.parse('http://x/v1/traces')));
      expect(r.headers['access-control-allow-headers'], contains('content-encoding'));
    });
  });
}

final class _Keys implements ArmIngestKeyRegistry {
  const _Keys();
  @override
  Future<bool> verify(String clientId, String key) async => clientId == 'client-a' && key == 'key-a';
}

final class _Router implements ArmProjectRouter {
  const _Router();
  @override
  Future<ArmProjectTarget> resolve(String projectId, {ArmRoutedOffering offering = ArmRoutedOffering.evidence}) async =>
      ArmProjectTarget(projectId: projectId, customerProjectId: 'customer-project', databaseId: offering.databaseId);
}

final class _Store implements ArmIngestStore {
  final List<ArmIngestCapture> captures = <ArmIngestCapture>[];
  @override
  Future<ArmIngestOutcome> record({
    required ArmProjectTarget target,
    required String caseId,
    required ArmIngestCapture capture,
    required ArmCaptureRequest request,
    required DateTime receivedAt,
  }) async {
    captures.add(capture);
    return ArmIngestOutcome(captureId: capture.captureId, caseId: caseId, issueId: 'issue', duplicate: false);
  }
}
