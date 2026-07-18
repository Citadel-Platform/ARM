import 'dart:typed_data';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:test/test.dart';

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

  group('sanitizeArmMap', () {
    test('trims large, deep, and custom values', () {
      final Map<String, dynamic>? sanitized = sanitizeArmMap(<String, dynamic>{
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
      });

      expect(sanitized, isNotNull);
      expect((sanitized!['oversized'] as String).length, 2000);
      expect((sanitized['list'] as List<dynamic>).length, 20);
      expect(sanitized['custom'], 'custom:serialized');
      expect(
        (((((sanitized['deep'] as Map<String, dynamic>)['a']
                        as Map<String, dynamic>)['b']
                    as Map<String, dynamic>)['c']
                as Map<String, dynamic>)['d']
            as Map<String, dynamic>)['e'],
        '{f: too-deep}',
      );
    });
  });

  group('ARM identifiers', () {
    test('buildArmIssueId is stable and buildArmSessionId honors prefixes', () {
      final String issueIdA = buildArmIssueId('fingerprint-a');
      final String issueIdB = buildArmIssueId('fingerprint-a');
      final String sessionId = buildArmSessionId(
        'citadel-platform',
        prefix: 'server-session',
      );

      expect(issueIdA, issueIdB);
      expect(issueIdA, startsWith('issue_'));
      expect(sessionId, startsWith('server-session-'));
    });

    test('buildArmCaseId emits ARM-prefixed identifiers', () {
      expect(buildArmCaseId(), matches(RegExp(r'^ARM-\d{8}-[A-F0-9]{8}$')));
    });
  });

  group('document builders', () {
    test('build shared case and issue payload maps', () {
      final ArmCaptureRequest request = ArmCaptureRequest(
        severity: ArmSeverity.serious,
        category: 'runtime',
        feature: 'server',
        operation: 'oauth_callback',
        message: 'Access denied',
        errorType: 'AccessDeniedException',
        errorName: 'AccessDeniedException',
        errorData: <String, dynamic>{'message': 'Access denied'},
        stackTrace: 'stack',
        fingerprint: 'fingerprint',
        sessionId: 'server-session-1',
        breadcrumbs: const <ArmBreadcrumb>[],
        context: <String, dynamic>{'environment': 'prod'},
        tags: <String, dynamic>{'tenant': 'alpha'},
        recoverySnapshot: <String, dynamic>{'phase': 'callback'},
        screenshot: ArmBinaryAttachment(
          bytes: Uint8List(0),
          contentType: 'image/png',
          extension: 'png',
          name: 'capture',
        ),
        appVersion: '2.4.0',
        buildNumber: '187',
        releaseChannel: 'stable',
        handled: true,
      );

      final Map<String, dynamic> issue = buildArmIssueDocumentMap(
        issueId: 'issue_123',
        caseId: 'ARM-20260626-ABCDEFGH',
        request: request,
        firstSeenAt: '2026-06-26T00:00:00.000Z',
        lastSeenAt: '2026-06-26T01:00:00.000Z',
        firstCaseId: 'ARM-20260626-ABCDEFGH',
        caseCount: 2,
      );
      final Map<String, dynamic> casePayload = buildArmCaseDocumentMap(
        caseId: 'ARM-20260626-ABCDEFGH',
        issueId: 'issue_123',
        request: request,
        createdAt: '2026-06-26T01:00:00.000Z',
        screenshotPath: 'arm/cases/issue_123/ARM-20260626-ABCDEFGH/capture.png',
      );

      expect(issue['caseCount'], 2);
      expect(issue['firstCaseId'], 'ARM-20260626-ABCDEFGH');
      expect(issue['appVersion'], '2.4.0');
      expect(issue['buildNumber'], '187');
      expect(issue['releaseChannel'], 'stable');
      expect(casePayload['errorName'], 'AccessDeniedException');
      expect(casePayload['errorData'], <String, dynamic>{
        'message': 'Access denied',
      });
      expect(
        (casePayload['screenshot'] as Map<String, dynamic>)['path'],
        contains('capture.png'),
      );
      expect(casePayload['handled'], isTrue);
    });
  });
}

class _CustomValue {
  const _CustomValue(this.value);

  final String value;

  @override
  String toString() => 'custom:$value';
}
