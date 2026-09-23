import 'dart:io';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// ARM's public ingest (decided 23/09/26).
///
/// One service in `citadel-platform`, shared by every client, open to anyone:
/// what authenticates a caller is the client ID and ARM ingest key checked
/// against the registry, not Cloud Run IAM. Its identity reads the registry
/// and writes each client's `citadel-arm` under a grant conditioned on that
/// one database. Same image as the private evidence service, different binary
/// and a different identity — the evidence service can read a client's
/// evidence, this one cannot be asked to.
Future<void> main() async {
  final String registryProjectId = _required('CITADEL_REGISTRY_PROJECT_ID');
  final int perMinute =
      int.tryParse(Platform.environment['CITADEL_ARM_INGEST_CAPTURES_PER_MINUTE'] ?? '') ??
      600;

  final AutoRefreshingAuthClient authClient = await clientViaApplicationDefaultCredentials(
    scopes: <String>[firestore_api.FirestoreApi.datastoreScope],
  );
  final firestore_api.FirestoreApi firestoreApi = firestore_api.FirestoreApi(authClient);

  final ArmIngestService service = ArmIngestService(
    keys: FirestoreArmIngestKeyRegistry(
      firestoreApi: firestoreApi,
      registryProjectId: registryProjectId,
    ),
    router: FirestoreArmProjectRouter(
      firestoreApi: firestoreApi,
      registryProjectId: registryProjectId,
    ),
    store: FirestoreArmIngestStore(firestoreApi: firestoreApi),
    rateLimiter: ArmIngestRateLimiter(capturesPerMinute: perMinute),
  );

  final Handler handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(createArmIngestHandler(service: service));
  final int port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final HttpServer server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    authClient.close();
  });
  stdout.writeln(
    'Citadel ARM ingest listening on port ${server.port} for registry '
    '$registryProjectId, $perMinute captures per client per minute per instance.',
  );
}

String _required(String name) {
  final String? value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('$name is required.');
    exit(78);
  }
  return value;
}
