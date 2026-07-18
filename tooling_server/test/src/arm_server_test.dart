import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arm_tooling_server/arm_tooling_server.dart';
import 'package:test/test.dart';

void main() {
  group('describeArmServerError', () {
    test('normalizes map payloads and server request failures', () {
      final ArmServerErrorDetails fromMap = describeArmServerError(
        <String, Object?>{
          'errorName': 'OAuthFailure',
          'message': 'access denied',
          'payload': <String, Object?>{'scope': 'gmail.readonly'},
        },
      );
      final ArmServerErrorDetails fromServerFailure = describeArmServerError(
        ServerRequestFailedException(
          message: 'token exchange failed',
          statusCode: 401,
          responseContent: <String, Object?>{
            'error': 'invalid_grant',
            'error_description': 'expired code',
          },
        ),
      );

      expect(fromMap.name, 'OAuthFailure');
      expect(fromMap.message, 'access denied');
      expect(
        (fromMap.data['payload'] as Map<String, dynamic>)['scope'],
        'gmail.readonly',
      );
      expect(fromServerFailure.name, 'ServerRequestFailedException');
      expect(fromServerFailure.data['statusCode'], 401);
      expect(fromServerFailure.data['oauthError'], 'invalid_grant');
    });
  });

  group('ArmServer', () {
    test(
      'captures normalized server errors with session context and severity gating',
      () async {
        final _FakeArmSink sink = _FakeArmSink();
        final ArmServer server = ArmServer(
          sink: sink,
          appId: 'citadel-api',
          environment: 'production',
          appVersion: ' 3.1.0 ',
          buildNumber: ' 912 ',
          releaseChannel: ' canary ',
          caseIdExposureThreshold: ArmSeverity.serious,
          contextBuilder: () => <String, dynamic>{
            'service': 'oauth-api',
            'sessionId': 'spoofed',
          },
        );

        final ArmCaptureResult result = await server.captureException(
          error: AccessDeniedException('Operator cannot access tenant'),
          stackTrace: StackTrace.current,
          feature: 'oauth',
          operation: 'callback',
          severity: ArmSeverity.moderate,
          context: <String, dynamic>{'requestId': 'req-42', 'userId': 'uid-77'},
        );

        final ArmCaptureRequest request = sink.requests.single;
        expect(request.errorName, 'AccessDeniedException');
        expect(request.errorType, 'AccessDeniedException');
        expect(request.errorData, <String, dynamic>{
          'message': 'Operator cannot access tenant',
        });
        expect(request.context['service'], 'oauth-api');
        expect(request.context['requestId'], 'req-42');
        expect(request.context['userId'], 'uid-77');
        expect(request.context['sessionId'], startsWith('server-session-'));
        expect(request.appVersion, '3.1.0');
        expect(request.buildNumber, '912');
        expect(request.releaseChannel, 'canary');
        expect(request.context['appVersion'], '3.1.0');
        expect(result.caseIdExposed, isFalse);

        final Map<String, dynamic> session =
            request.context['session'] as Map<String, dynamic>;
        expect(session['id'], request.context['sessionId']);
        expect(session['appId'], 'citadel-api');
        expect(session['environment'], 'production');
        expect(session['runtime'], 'server');
        expect(session['releaseChannel'], 'canary');
      },
    );

    test('runTracked records handled exceptions before rethrowing', () async {
      final _FakeArmSink sink = _FakeArmSink();
      final ArmServer server = ArmServer(
        sink: sink,
        appId: 'citadel-api',
        environment: 'production',
      );

      ArmCaptureResult? callbackResult;

      await expectLater(
        () => server.runTracked<void>(
          feature: 'jobs',
          operation: 'sync_inbox',
          severity: ArmSeverity.serious,
          action: () async {
            throw StateError('sync failed');
          },
          onReported: (ArmCaptureResult result) {
            callbackResult = result;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(sink.requests.single.handled, isTrue);
      expect(callbackResult, isNotNull);
      expect(callbackResult!.caseIdExposed, isTrue);
    });
  });

  test('buildArmRequestContext captures request metadata', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<Map<String, dynamic>> contextFuture = server.first.then((
      HttpRequest request,
    ) async {
      final context = buildArmRequestContext(
        request,
        userId: ' uid-88 ',
        userEmail: ' ops@citadel.dev ',
        requestId: ' req-9 ',
        traceId: ' trace-1 ',
        extra: <String, dynamic>{'tenant': 'alpha'},
      );
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return context;
    });

    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.postUrl(
      Uri.parse(
        'http://${server.address.address}:${server.port}/oauth/callback?flow=google',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.userAgentHeader, 'arm-test-agent');
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    final Map<String, dynamic> context = await contextFuture;

    expect(context['tenant'], 'alpha');
    expect(context['userId'], 'uid-88');
    expect(context['userEmail'], 'ops@citadel.dev');
    expect(context['requestId'], 'req-9');
    expect(context['traceId'], 'trace-1');
    expect((context['request'] as Map<String, dynamic>)['method'], 'POST');
    expect(
      (context['request'] as Map<String, dynamic>)['path'],
      '/oauth/callback',
    );
    expect(
      (context['request'] as Map<String, dynamic>)['query'],
      'flow=google',
    );
    expect(
      (context['request'] as Map<String, dynamic>)['contentType'],
      'application/json',
    );

    client.close(force: true);
    await server.close(force: true);
  });

  test('ArmHttpMiddleware.wrap records request failures', () async {
    final _FakeArmSink sink = _FakeArmSink();
    final ArmServer armServer = ArmServer(
      sink: sink,
      appId: 'citadel-api',
      environment: 'production',
    );
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> handler = server.first.then((HttpRequest request) async {
      try {
        await ArmHttpMiddleware.wrap<void>(
          server: armServer,
          request: request,
          feature: 'oauth',
          operation: 'callback',
          userId: 'uid-11',
          requestId: 'req-77',
          action: () async {
            throw AccessDeniedException('Denied');
          },
        );
      } catch (_) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    });

    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(
      Uri.parse(
        'http://${server.address.address}:${server.port}/oauth/callback',
      ),
    );
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    await handler;

    expect(sink.requests, hasLength(1));
    expect(
      (sink.requests.single.context['request'] as Map<String, dynamic>)['path'],
      '/oauth/callback',
    );
    expect(sink.requests.single.context['userId'], 'uid-11');
    expect(sink.requests.single.context['requestId'], 'req-77');

    client.close(force: true);
    await server.close(force: true);
  });

  test('respondArmJson exposes the case id only when allowed', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> handler = server.first.then((HttpRequest request) async {
      await respondArmJson(
        request,
        statusCode: HttpStatus.badGateway,
        body: <String, Object?>{'error': 'upstream failed'},
        capture: const ArmCaptureResult(
          caseId: 'ARM-20260626-ABCDEFGH',
          issueId: 'issue_123',
          fingerprint: 'fp',
          severity: ArmSeverity.serious,
          caseIdExposed: true,
        ),
      );
    });

    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(
      Uri.parse('http://${server.address.address}:${server.port}/fail'),
    );
    final HttpClientResponse response = await request.close();
    final Map<String, dynamic> body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    await handler;

    expect(response.statusCode, HttpStatus.badGateway);
    expect(
      response.headers.value(armCaseIdHeaderName),
      'ARM-20260626-ABCDEFGH',
    );
    expect(body['armCaseId'], 'ARM-20260626-ABCDEFGH');

    client.close(force: true);
    await server.close(force: true);
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
