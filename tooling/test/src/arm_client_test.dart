import 'package:arm_tooling/arm_tooling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildArmFingerprint', () {
    test('stays stable across numeric and hex variations', () {
      final StackTrace stackTraceA = StackTrace.fromString(
        '#0      submitPayment (package:citadel/app.dart:10:2)\n'
        '#1      <asynchronous suspension>\n'
        '#2      checkout (package:citadel/checkout.dart:30:8)\n',
      );
      final StackTrace stackTraceB = StackTrace.fromString(
        '#0      submitPayment (package:citadel/app.dart:88:4)\n'
        '#1      <asynchronous suspension>\n'
        '#2      checkout (package:citadel/checkout.dart:91:9)\n',
      );

      final String fingerprintA = buildArmFingerprint(
        feature: 'checkout',
        operation: 'submit_payment',
        errorType: 'StateError',
        message: 'Payment failed for order 9817 at pointer 0xAABBCCDD',
        stackTrace: stackTraceA,
      );
      final String fingerprintB = buildArmFingerprint(
        feature: 'checkout',
        operation: 'submit_payment',
        errorType: 'StateError',
        message: 'Payment failed for order 1042 at pointer 0x00112233',
        stackTrace: stackTraceB,
      );

      expect(fingerprintA, fingerprintB);
      expect(fingerprintA, isNot(contains('9817')));
      expect(fingerprintA, isNot(contains('0xAABBCCDD')));
    });
  });

  group('ArmClient', () {
    test('exposes case ids only from moderate severity upward', () async {
      final _FakeArmSink sink = _FakeArmSink();
      final ArmClient client = ArmClient(
        sink: sink,
        appId: 'citadel-platform',
        environment: 'test',
      );

      final ArmCaptureResult lowResult = await client.captureException(
        error: StateError('low severity'),
        stackTrace: StackTrace.current,
        feature: 'overview',
        operation: 'refresh',
        severity: ArmSeverity.low,
      );
      final ArmCaptureResult moderateResult = await client.captureException(
        error: StateError('moderate severity'),
        stackTrace: StackTrace.current,
        feature: 'overview',
        operation: 'refresh',
        severity: ArmSeverity.moderate,
      );

      expect(lowResult.caseIdExposed, isFalse);
      expect(moderateResult.caseIdExposed, isTrue);
    });

    test(
      'sanitizes large and deep context values before sending them to the sink',
      () async {
        final _FakeArmSink sink = _FakeArmSink();
        final ArmClient client = ArmClient(
          sink: sink,
          appId: 'citadel-platform',
          environment: 'test',
          contextBuilder: () => <String, dynamic>{
            'route': '/console/arm',
            'nested': <String, dynamic>{
              'list': List<int>.generate(30, (int index) => index),
            },
          },
        );

        await client.captureException(
          error: StateError('context test'),
          stackTrace: StackTrace.current,
          feature: 'console',
          operation: 'save_filters',
          tags: <String, dynamic>{
            'oversized': 'x' * 2505,
            'list': List<int>.generate(25, (int index) => index),
            'custom': _CustomValue('serialized'),
            'deep': <String, dynamic>{
              'a': <String, dynamic>{
                'b': <String, dynamic>{
                  'c': <String, dynamic>{
                    'd': <String, dynamic>{
                      'e': <String, dynamic>{'f': 'too-deep'},
                    },
                  },
                },
              },
            },
          },
        );

        final ArmCaptureRequest request = sink.requests.single;
        expect((request.tags['oversized'] as String).length, 2000);
        expect((request.tags['list'] as List<dynamic>).length, 20);
        expect(request.tags['custom'], 'custom:serialized');
        expect(
          (((request.tags['deep'] as Map<String, dynamic>)['a']
                  as Map<String, dynamic>)['b']
              as Map<String, dynamic>)['c'],
          isA<Map<String, dynamic>>(),
        );
        expect(
          ((((request.tags['deep'] as Map<String, dynamic>)['a']
                      as Map<String, dynamic>)['b']
                  as Map<String, dynamic>)['c']
              as Map<String, dynamic>)['d'],
          isA<Map<String, dynamic>>(),
        );
        expect(
          (((((request.tags['deep'] as Map<String, dynamic>)['a']
                          as Map<String, dynamic>)['b']
                      as Map<String, dynamic>)['c']
                  as Map<String, dynamic>)['d']
              as Map<String, dynamic>)['e'],
          '{f: too-deep}',
        );
        expect(
          ((request.context['nested'] as Map<String, dynamic>)['list']
                  as List<dynamic>)
              .length,
          20,
        );
      },
    );

    test(
      'captures session context including current user identity and keeps SDK-owned keys authoritative',
      () async {
        final _FakeArmSink sink = _FakeArmSink();
        final ArmClient client = ArmClient(
          sink: sink,
          appId: 'citadel-platform',
          environment: 'test',
          appVersion: ' 2.4.0 ',
          buildNumber: ' 187 ',
          releaseChannel: ' stable ',
          userIdProvider: () => ' uid-42 ',
          userEmailProvider: () => ' ops@citadel.internal ',
          routeProvider: () => ' /arm/issues ',
          contextBuilder: () => <String, dynamic>{
            'sessionId': 'host-session',
            'userId': 'host-user',
            'userEmail': 'host@example.com',
            'route': '/wrong-route',
            'screen': 'issue-detail',
          },
        );

        await client.captureException(
          error: StateError('session context'),
          stackTrace: StackTrace.current,
          feature: 'console',
          operation: 'open_issue',
        );

        final ArmCaptureRequest request = sink.requests.single;
        expect(request.context['appId'], 'citadel-platform');
        expect(request.context['environment'], 'test');
        expect(request.context['sessionId'], startsWith('session-'));
        expect(request.context['userId'], 'uid-42');
        expect(request.context['userEmail'], 'ops@citadel.internal');
        expect(request.context['route'], '/arm/issues');
        expect(request.context['screen'], 'issue-detail');
        expect(request.appVersion, '2.4.0');
        expect(request.buildNumber, '187');
        expect(request.releaseChannel, 'stable');
        expect(request.context['appVersion'], '2.4.0');

        final Map<String, dynamic> session =
            request.context['session'] as Map<String, dynamic>;
        expect(session['id'], request.context['sessionId']);
        expect(session['appId'], 'citadel-platform');
        expect(session['environment'], 'test');
        expect(session['userId'], 'uid-42');
        expect(session['userEmail'], 'ops@citadel.internal');
        expect(session['route'], '/arm/issues');
        expect(session['appVersion'], '2.4.0');
      },
    );

    test(
      'runTracked records handled exceptions and invokes onReported',
      () async {
        final _FakeArmSink sink = _FakeArmSink();
        final ArmClient client = ArmClient(
          sink: sink,
          appId: 'citadel-platform',
          environment: 'test',
        );

        ArmCaptureResult? callbackResult;

        await expectLater(
          () => client.runTracked<void>(
            feature: 'settings',
            operation: 'save_profile',
            severity: ArmSeverity.serious,
            action: () async {
              throw StateError('boom');
            },
            onReported: (ArmCaptureResult result) {
              callbackResult = result;
            },
          ),
          throwsA(isA<StateError>()),
        );

        expect(sink.requests.single.handled, isTrue);
        expect(callbackResult, isNotNull);
        expect(callbackResult!.severity, ArmSeverity.serious);
      },
    );
  });
}

class _FakeArmSink implements ArmSink {
  final List<ArmCaptureRequest> requests = <ArmCaptureRequest>[];

  @override
  Future<ArmCaptureResult> record(ArmCaptureRequest request) async {
    requests.add(request);
    return ArmCaptureResult(
      caseId: 'ARM-TEST-0001',
      issueId: 'issue_test',
      fingerprint: request.fingerprint,
      severity: request.severity,
      caseIdExposed: request.severity.exposesCaseId,
    );
  }
}

class _CustomValue {
  const _CustomValue(this.value);

  final String value;

  @override
  String toString() => 'custom:$value';
}
