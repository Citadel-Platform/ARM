import 'dart:io';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Private ARM evidence runtime.
///
/// Cloud Run IAM is the first gate: only the Platform API runtime identity holds
/// `roles/run.invoker`. The service then re-verifies the caller's identity token
/// itself so an ingress misconfiguration cannot open the customer boundary.
Future<void> main() async {
  final audience = _required('CITADEL_ARM_SERVICE_AUDIENCE');
  final registryProjectId = _required('CITADEL_REGISTRY_PROJECT_ID');
  final allowedCallers = _requiredSet('CITADEL_ARM_ALLOWED_CALLERS');
  final maxScanDocuments =
      int.tryParse(Platform.environment['CITADEL_ARM_MAX_SCAN_DOCUMENTS'] ?? '') ??
      armDefaultMaxScanDocuments;

  final authClient = await clientViaApplicationDefaultCredentials(
    scopes: <String>[firestore_api.FirestoreApi.datastoreScope],
  );
  final firestoreApi = firestore_api.FirestoreApi(authClient);

  final service = ArmPrivateService(
    repository: FirestoreArmEvidenceRepository(
      firestoreApi: firestoreApi,
      router: FirestoreArmProjectRouter(
        firestoreApi: firestoreApi,
        registryProjectId: registryProjectId,
      ),
      // Alerting configuration lives in the registry project, never in a
      // client's own database: it decides who Citadel sends messages to.
      registryProjectId: registryProjectId,
      maxScanDocuments: maxScanDocuments,
    ),
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        createArmPrivateServiceHandler(
          service: service,
          authorizer: createGoogleOidcArmAuthorizer(
            expectedAudience: audience,
            allowedCallerEmails: allowedCallers,
          ),
        ),
      );

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Citadel ARM evidence service listening on port ${server.port} '
    'for registry $registryProjectId.',
  );
}

String _required(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('$name is required.');
    exit(78);
  }
  return value;
}

Set<String> _requiredSet(String name) {
  final values = _required(name)
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (values.isEmpty) {
    stderr.writeln('$name must list at least one value.');
    exit(78);
  }
  return values;
}
