@Tags(<String>['emulator'])
library;

import 'dart:io';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The ticket store against real Firestore semantics, and the join the unit
/// tests cannot reach.
///
/// The SDK writes a ticket into the client's own database from a device, and
/// this service reads it back. The contract test holds the two *shapes*
/// together; only this holds them together through one Firestore — which is
/// the exact class of gap Phase R cost five production-fatal defects to learn.
void main() {
  final String host = Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '';
  final String? skip = host.isEmpty
      ? 'Set FIRESTORE_EMULATOR_HOST to run this against the emulator.'
      : null;

  test('a ticket the SDK writes is one the service lists and works', skip: skip,
      () async {
    final firestore_api.FirestoreApi api = firestore_api.FirestoreApi(
      _EmulatorAdminClient(),
      rootUrl: 'http://$host/',
    );
    final String documentsRoot =
        'projects/$_project/databases/(default)/documents';

    // What the device writes, byte for byte: the SDK's own document builder,
    // through the same REST API the SDK's Firestore client uses.
    final String ticketId = buildArmTicketId();
    final Map<String, dynamic> document = buildArmTicketDocumentMap(
      ticketId: ticketId,
      updateId: '${ticketId}_1',
      request: ArmTicketRequest(
        title: 'Checkout will not submit',
        description: 'It spins and then nothing happens.',
        contact: 'buyer@example.com',
        caseId: buildArmCaseId(),
        issueId: buildArmIssueId('fingerprint'),
        sessionId: buildArmSessionId('citadel-platform'),
      ),
      createdAt: DateTime.utc(2026, 8, 31, 3),
      indexedUpdatedAt: DateTime.utc(2026, 8, 31, 3).toIso8601String(),
    );
    final String name = '$documentsRoot/$armTicketsCollectionId/$ticketId';
    await api.projects.databases.documents.patch(
      firestore_api.Document(
        name: name,
        fields: <String, firestore_api.Value>{
          'ticketId': firestore_api.Value(
            stringValue: document['ticketId'] as String,
          ),
          'ticket': firestore_api.Value(
            stringValue: document['ticket'] as String,
          ),
          'status': firestore_api.Value(
            stringValue: document['status'] as String,
          ),
          'updatedAt': firestore_api.Value(
            timestampValue: document['updatedAt'] as String,
          ),
        },
      ),
      name,
    );

    final ArmEvidenceRepository repository = FirestoreArmEvidenceRepository(
      firestoreApi: api,
      router: const _FixedRouter(),
      registryProjectId: _project,
    );

    final ArmTicketRecord? read = await repository.getTicket(
      projectId: 'client-a',
      ticketId: ticketId,
    );
    expect(read, isNotNull);
    expect(read!.title, 'Checkout will not submit');
    expect(read.updates.single.authorKind, ArmTicketAuthorKind.endUser);
    expect(read.status, ArmTicketStatus.open);

    // And it is in the listing, which is where an operator actually finds it.
    final ArmTicketPageSlice listed = await repository.listTickets(
      projectId: 'client-a',
      query: const ArmTicketQuery(),
    );
    expect(
      listed.tickets.map((ArmTicketRecord value) => value.ticketId),
      contains(ticketId),
    );

    // Working it writes the whole ticket back, history and all.
    final ArmPrivateService service = ArmPrivateService(
      repository: repository,
      clock: () => DateTime.utc(2026, 8, 31, 4),
    );
    final ArmTicketRecord replied = await service.appendTicketUpdate(
      projectId: 'client-a',
      ticketId: ticketId,
      draft: const ArmTicketUpdateDraft(
        authorKind: ArmTicketAuthorKind.operator,
        body: 'Looking at it now.',
      ),
      authorLabel: 'operator@example.com',
    );
    expect(replied.updates.length, 2);

    final ArmTicketRecord? reread = await repository.getTicket(
      projectId: 'client-a',
      ticketId: ticketId,
    );
    // The customer's first message survives the operator's reply: a partial
    // write of a history is a history with a hole in it.
    expect(reread!.updates.first.body, 'It spins and then nothing happens.');
    expect(reread.updates.last.authorLabel, 'operator@example.com');
  });
}

const String _project = 'demo-citadel-arm';

/// Routes every project at one emulator database, so the test exercises the
/// repository rather than the registry lookup the unit tests already cover.
final class _FixedRouter implements ArmProjectRouter {
  const _FixedRouter();

  @override
  Future<ArmProjectTarget> resolve(String projectId) async =>
      const ArmProjectTarget(
        projectId: _project,
        customerProjectId: _project,
        databaseId: '(default)',
      );
}

/// Reaches the emulator the way the deployed service reaches Firestore: as an
/// administrative caller whose credentials bypass the security rules.
final class _EmulatorAdminClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}
