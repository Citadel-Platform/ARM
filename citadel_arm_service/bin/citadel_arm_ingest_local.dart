import 'dart:io';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// The ARM ingest against the Firestore emulator, for driving it from a real
/// browser on another origin — the only way to prove CORS and the unload
/// beacon (`G4-56`).
///
///   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run bin/citadel_arm_ingest_local.dart
///
/// The ingest, handler and Firestore store are the shipped ones. Two things
/// stand in: the key registry holds one key (`ARM_LOCAL_CLIENT`,
/// `ARM_LOCAL_KEY`), and the router sends that client to the emulator's
/// `(default)` database. Optionally serves the browser bundles from
/// `ARM_LOCAL_SDK_DIR` at `/sdk/v1/`.
Future<void> main() async {
  final String host = Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final String client = Platform.environment['ARM_LOCAL_CLIENT'] ?? 'local-client';
  final String key = Platform.environment['ARM_LOCAL_KEY'] ?? 'arm-local-key';
  final String project = Platform.environment['ARM_LOCAL_PROJECT'] ?? 'demo-citadel-arm';
  final int port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8793;
  final firestore_api.FirestoreApi api = firestore_api.FirestoreApi(
    _EmulatorAdmin(),
    rootUrl: 'http://$host/',
  );
  final Handler ingest = createArmIngestHandler(
    service: ArmIngestService(
      keys: _OneKey(client, key),
      router: _Emulator(project),
      store: FirestoreArmIngestStore(firestoreApi: api),
      rateLimiter: ArmIngestRateLimiter(capturesPerMinute: 600),
    ),
  );
  final String? sdkDir = Platform.environment['ARM_LOCAL_SDK_DIR'];
  Future<Response> handler(Request request) async {
    final List<String> path = request.url.pathSegments;
    if (sdkDir != null && request.method == 'GET' && path.length == 3 && path[0] == 'sdk') {
      final File file = File('$sdkDir/${path[2]}');
      if (!path[2].contains('/') && file.existsSync()) {
        return Response.ok(
          file.readAsBytesSync(),
          headers: const <String, String>{
            'content-type': 'application/javascript; charset=utf-8',
            'access-control-allow-origin': '*',
          },
        );
      }
    }
    return ingest(request);
  }

  final HttpServer server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(handler),
    InternetAddress.loopbackIPv4,
    port,
  );
  stdout
    ..writeln('ARM ingest (local, emulator-backed) on http://127.0.0.1:${server.port}')
    ..writeln('  Client ID  : $client')
    ..writeln('  Ingest key : $key')
    ..writeln('  Writes to  : $project (default) on $host');
}

final class _OneKey implements ArmIngestKeyRegistry {
  const _OneKey(this.client, this.key);
  final String client;
  final String key;
  @override
  Future<bool> verify(String clientId, String presented) async =>
      clientId == client && presented == key;
}

final class _Emulator implements ArmProjectRouter {
  const _Emulator(this.project);
  final String project;
  @override
  Future<ArmProjectTarget> resolve(
    String projectId, {
    ArmRoutedOffering offering = ArmRoutedOffering.evidence,
  }) async => ArmProjectTarget(
    projectId: projectId,
    customerProjectId: project,
    databaseId: '(default)',
  );
}

final class _EmulatorAdmin extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}
