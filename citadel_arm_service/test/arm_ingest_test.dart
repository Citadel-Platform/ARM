import 'dart:convert';

import 'package:arm_tooling_core/arm_tooling_core.dart' as core;
import 'package:arm_tooling_core/arm_tooling_core.dart'
    show ArmCaptureRequest, buildArmIssueId;
import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime.utc(2026, 9, 23, 12);

Map<String, Object?> capture({
  String captureId = 'cap-1',
  String message = 'Cannot read properties of undefined (reading \'slots\')',
  String stack =
      "TypeError: Cannot read properties of undefined (reading 'slots')\n"
      '    at renderSlots (https://book.example/_next/static/chunks/page-3f9a1c.js:1:20488)',
  String? occurredAt,
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  'captureId': captureId,
  'occurredAt': occurredAt ?? _now.toIso8601String(),
  'source': 'web',
  'severity': 'moderate',
  'feature': 'booking',
  'operation': 'load_slots',
  'errorType': 'TypeError',
  'message': message,
  'stackTrace': stack,
  'sessionId': 'session-1',
  'breadcrumbs': <Object?>[
    <String, Object?>{
      'message': 'GET https://api.book.example/slots → 500',
      'level': 'error',
      'timestamp': _now.toIso8601String(),
      'category': 'network',
    },
    <String, Object?>{'message': 'no timestamp, dropped'},
  ],
  ...extra,
};

void main() {
  group('parsing', () {
    test('a well-formed capture parses, and a malformed crumb is dropped', () {
      final List<ArmIngestCapture> parsed = parseArmIngestBatch(
        <Object?>[capture()],
        now: _now,
      );
      expect(parsed.single.severity, core.ArmSeverity.moderate);
      expect(parsed.single.source, ArmCaptureSource.web);
      expect(parsed.single.breadcrumbs, hasLength(1));
    });

    test('refusals name the field', () {
      expect(
        () => parseArmIngestBatch(<Object?>[
          capture(extra: <String, Object?>{'feature': ''}),
        ], now: _now),
        throwsA(
          isA<ArmIngestRejection>()
              .having((r) => r.status, 'status', 400)
              .having((r) => r.message, 'message', contains('feature')),
        ),
      );
      expect(
        () => parseArmIngestBatch(<Object?>[
          capture(extra: <String, Object?>{'severity': 'panic'}),
        ], now: _now),
        throwsA(isA<ArmIngestRejection>()),
      );
      expect(
        () => parseArmIngestBatch(<String, Object?>{}, now: _now),
        throwsA(isA<ArmIngestRejection>()),
      );
      expect(
        () => parseArmIngestBatch(
          List<Object?>.generate(21, (i) => capture(captureId: 'c$i')),
          now: _now,
        ),
        throwsA(isA<ArmIngestRejection>().having((r) => r.status, 's', 413)),
      );
    });

    test('an implausible client clock is replaced by the arrival time', () {
      final ArmIngestCapture future = parseArmIngestBatch(<Object?>[
        capture(occurredAt: '2027-01-01T00:00:00Z'),
      ], now: _now).single;
      expect(future.occurredAt, _now);
    });
  });

  group('grouping', () {
    test('a V8 stack groups across differing numbers and bundle hashes', () {
      final a = armCaptureRequestFor(
        parseArmIngestBatch(<Object?>[
          capture(
            message: 'Order 9817 failed',
            stack:
                'TypeError: Order 9817 failed\n'
                '    at pay (https://x.example/_next/static/chunks/page-3f9a1c.js:1:20488)\n'
                '    at main (https://x.example/main.8e2a1b4c.js:2:10)',
          ),
        ], now: _now).single,
      );
      final b = armCaptureRequestFor(
        parseArmIngestBatch(<Object?>[
          capture(
            message: 'Order 1042 failed',
            stack:
                'TypeError: Order 1042 failed\n'
                '    at pay (https://x.example/_next/static/chunks/page-77aa00.js:1:9)\n'
                '    at main (https://x.example/main.1234abcd.js:5:3)',
          ),
        ], now: _now).single,
      );
      expect(a.fingerprint, b.fingerprint);
      // The case keeps the stack exactly as it arrived.
      expect(a.stackTrace, contains('page-3f9a1c.js'));
    });

    test('a query string in a frame does not split one fault', () {
      final a = armCaptureRequestFor(parseArmIngestBatch(<Object?>[
        capture(stack: 'TypeError: x\n    at onclick (https://x.example/?a=1&t=secret:8:60)'),
      ], now: _now).single);
      final b = armCaptureRequestFor(parseArmIngestBatch(<Object?>[
        capture(stack: 'TypeError: x\n    at onclick (https://x.example/?a=2:8:60)'),
      ], now: _now).single);
      expect(a.fingerprint, b.fingerprint);
      expect(a.fingerprint, isNot(contains('secret')));
    });

    test('a Dart stack is fingerprinted by the reference unchanged', () {
      final ArmIngestCapture dart = parseArmIngestBatch(<Object?>[
        capture(extra: <String, Object?>{'source': 'dart'}, stack: 'TypeError: x\n#0 f (a.dart:1:1)'),
      ], now: _now).single;
      expect(armFingerprintStack(dart), dart.stackTrace);
    });

    test('a case id is the tooling_core format and stable for a redelivery', () {
      final ArmIngestCapture c = parseArmIngestBatch(<Object?>[capture()], now: _now).single;
      final String id = armIngestCaseId('client-a', c);
      expect(id, matches(RegExp(r'^ARM-20260923-[0-9A-F]{8}$')));
      expect(armIngestCaseId('client-a', c), id);
      expect(armIngestCaseId('client-b', c), isNot(id));
    });
  });

  group('service', () {
    late _MemoryStore store;
    late ArmIngestService service;

    ArmIngestService build({
      ArmProjectRouter router = const _Router(),
      int perMinute = 100,
    }) => ArmIngestService(
      keys: const _Keys(<String, String>{'client-a': 'key-a'}),
      router: router,
      store: store,
      rateLimiter: ArmIngestRateLimiter(capturesPerMinute: perMinute, clock: () => _now),
      clock: () => _now,
    );

    setUp(() {
      store = _MemoryStore();
      service = build();
    });

    test('an unknown client and a wrong key get the same answer', () async {
      Future<ArmIngestRejection> refusal(String client, String key) async {
        try {
          await service.accept(clientId: client, key: key, body: <Object?>[capture()]);
        } on ArmIngestRejection catch (r) {
          return r;
        }
        fail('accepted');
      }

      final ArmIngestRejection unknown = await refusal('client-z', 'key-a');
      final ArmIngestRejection wrong = await refusal('client-a', 'key-b');
      expect(unknown.status, 401);
      expect(wrong.message, unknown.message);
      expect(store.records, isEmpty);
    });

    test('a switched-off ARM is 409, as every product answers', () async {
      service = build(router: const _Router(off: true));
      await expectLater(
        service.accept(clientId: 'client-a', key: 'key-a', body: <Object?>[capture()]),
        throwsA(isA<ArmIngestRejection>().having((r) => r.status, 's', 409)),
      );
    });

    test('the per-client ceiling answers 429', () async {
      service = build(perMinute: 1);
      await service.accept(clientId: 'client-a', key: 'key-a', body: <Object?>[capture()]);
      await expectLater(
        service.accept(clientId: 'client-a', key: 'key-a', body: <Object?>[capture(captureId: 'c2')]),
        throwsA(isA<ArmIngestRejection>().having((r) => r.status, 's', 429)),
      );
    });
  });

  test('environment survives the evidence JSON both ways', () {
    // Stored all along, and dropped by the encoder until 23/09/26: found
    // reading back the ingest's first production capture. The Console decodes
    // with this same codec, so encoder and decoder change together.
    final ArmIssueRecord issue = ArmIssueRecord(
      issueId: 'issue_abc',
      severity: 'moderate',
      category: 'exception',
      feature: 'f',
      operation: 'o',
      firstSeenAt: _now,
      lastSeenAt: _now,
      caseCount: 1,
      environment: 'staging',
    );
    expect(decodeArmIssueRecord(encodeArmIssueRecord(issue)).environment, 'staging');
    expect(encodeArmIssueRecord(issue.copyWith(environment: null)).containsKey('environment'), isFalse);
  });

  group('handler', () {
    late Handler handler;
    late _MemoryStore store;

    setUp(() {
      store = _MemoryStore();
      handler = createArmIngestHandler(
        service: ArmIngestService(
          keys: const _Keys(<String, String>{'client-a': 'key-a'}),
          router: const _Router(),
          store: store,
          rateLimiter: ArmIngestRateLimiter(capturesPerMinute: 100),
          clock: () => _now,
        ),
      );
    });

    test('a browser preflight names the ARM headers', () async {
      final Response response = await handler(
        Request('OPTIONS', Uri.parse('http://x/v1/captures')),
      );
      expect(response.statusCode, 204);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(response.headers['access-control-allow-headers'], contains('x-arm-key'));
      expect(response.headers['access-control-allow-headers'], contains('x-citadel-client'));
    });

    test('headers authenticate a batch, and the answer names the cases', () async {
      final Response response = await handler(
        Request(
          'POST',
          Uri.parse('http://x/v1/captures'),
          headers: <String, String>{'x-citadel-client': 'client-a', 'x-arm-key': 'key-a'},
          body: jsonEncode(<Object?>[capture()]),
        ),
      );
      expect(response.statusCode, 202);
      final Map<String, Object?> body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect(body['accepted'], 1);
      expect(((body['captures'] as List).single as Map)['caseId'], startsWith('ARM-'));
      expect(response.headers['access-control-allow-origin'], '*');
    });

    test('an unload beacon authenticates in the query, as text/plain', () async {
      final Response response = await handler(
        Request(
          'POST',
          Uri.parse('http://x/v1/captures?client=client-a&key=key-a'),
          headers: <String, String>{'content-type': 'text/plain;charset=UTF-8'},
          body: jsonEncode(<Object?>[capture()]),
        ),
      );
      expect(response.statusCode, 202);
      expect(store.records, hasLength(1));
    });

    test('the browser scripts are served, cached and revalidated', () async {
      final Handler withAssets = createArmIngestHandler(
        service: ArmIngestService(
          keys: const _Keys(<String, String>{}),
          router: const _Router(),
          store: store,
          rateLimiter: ArmIngestRateLimiter(capturesPerMinute: 1),
        ),
        sdkAssets: ArmSdkAssets.fromMap(<String, String>{'arm.js': 'window.x=1;'}),
      );
      final Response ok = await withAssets(Request('GET', Uri.parse('http://x/sdk/v1/arm.js')));
      expect(ok.statusCode, 200);
      expect(await ok.readAsString(), 'window.x=1;');
      expect(ok.headers['access-control-allow-origin'], '*');
      final Response again = await withAssets(Request(
        'GET',
        Uri.parse('http://x/sdk/v1/arm.js'),
        headers: <String, String>{'if-none-match': ok.headers['etag']!},
      ));
      expect(again.statusCode, 304);
      final Response missing = await handler(Request('GET', Uri.parse('http://x/sdk/v1/arm.js')));
      expect(missing.statusCode, 404);
      expect(await missing.readAsString(), contains('does not carry the web SDK'));
    });

    test('a failure is opaque and carries a request id', () async {
      final Response response = await handler(
        Request('POST', Uri.parse('http://x/v1/captures'), body: 'not json'),
      );
      expect(response.statusCode, 400);
      final Map<String, Object?> error =
          (jsonDecode(await response.readAsString()) as Map)['error'] as Map<String, Object?>;
      expect(error['requestId'], isNotNull);
    });
  });
}

final class _Keys implements ArmIngestKeyRegistry {
  const _Keys(this.keys);
  final Map<String, String> keys;
  @override
  Future<bool> verify(String clientId, String key) async => keys[clientId] == key;
}

final class _Router implements ArmProjectRouter {
  const _Router({this.off = false});
  final bool off;
  @override
  Future<ArmProjectTarget> resolve(
    String projectId, {
    ArmRoutedOffering offering = ArmRoutedOffering.evidence,
  }) async {
    if (off) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message: 'ARM is not enabled for this project.',
      );
    }
    return ArmProjectTarget(
      projectId: projectId,
      customerProjectId: 'customer-project',
      databaseId: offering.databaseId,
    );
  }
}

final class _MemoryStore implements ArmIngestStore {
  final Map<String, ArmCaptureRequest> records = <String, ArmCaptureRequest>{};
  @override
  Future<ArmIngestOutcome> record({
    required ArmProjectTarget target,
    required String caseId,
    required ArmIngestCapture capture,
    required ArmCaptureRequest request,
    required DateTime receivedAt,
  }) async {
    final bool duplicate = records.containsKey(caseId);
    records[caseId] = request;
    return ArmIngestOutcome(
      captureId: capture.captureId,
      caseId: caseId,
      issueId: buildArmIssueId(request.fingerprint),
      duplicate: duplicate,
    );
  }
}
