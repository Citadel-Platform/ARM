import 'dart:convert';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ARM tickets', () {
    test('opening one records the description as the first entry', () async {
      final repository = _TicketRepository();
      final service = _service(repository);

      final ticket = await service.createTicket(
        projectId: 'customer-ops',
        draft: const ArmTicketDraft(
          title: 'Checkout will not submit',
          description: 'It spins and then nothing happens.',
          reporterContact: 'buyer@example.com',
          caseIds: <String>['case_a'],
          issueId: 'issue_a',
        ),
        openedBy: 'citadel_arm_client',
        openedAs: ArmTicketAuthorKind.endUser,
      );

      expect(ticket.status, ArmTicketStatus.open);
      // A thread that began mid-sentence is a thread whose first message is
      // missing, so the description opens the history rather than only
      // sitting in a field.
      expect(ticket.updates.single.body, 'It spins and then nothing happens.');
      expect(ticket.updates.single.authorKind, ArmTicketAuthorKind.endUser);
      expect(ticket.updates.single.authorLabel, 'buyer@example.com');
      // The id is the service's, never the caller's.
      expect(ticket.ticketId, isNotEmpty);
      expect(repository.tickets.containsKey(ticket.ticketId), isTrue);
    });

    test('a closed ticket still accepts a reply', () async {
      final repository = _TicketRepository();
      final service = _service(repository);
      final opened = await service.createTicket(
        projectId: 'customer-ops',
        draft: const ArmTicketDraft(title: 'A', description: 'B'),
        openedBy: 'operator@example.com',
      );
      await service.updateTicketStatus(
        projectId: 'customer-ops',
        ticketId: opened.ticketId,
        status: ArmTicketStatus.closed,
        principal: _principal,
      );

      final replied = await service.appendTicketUpdate(
        projectId: 'customer-ops',
        ticketId: opened.ticketId,
        draft: const ArmTicketUpdateDraft(
          authorKind: ArmTicketAuthorKind.endUser,
          body: 'It happened again.',
        ),
        authorLabel: 'buyer@example.com',
      );

      // Refusing it would send the customer to a second ticket that nothing
      // links to the first.
      expect(replied.status, ArmTicketStatus.closed);
      expect(replied.updates.last.body, 'It happened again.');
      expect(replied.updatedAt.isAfter(replied.createdAt), isTrue);
    });

    test('a ticket with no allowlist is public and carries no evidence', () {
      final ticket = _ticket(
        allowlist: const <String>[],
        caseIds: const <String>['case_a'],
      );

      final decision = armTicketAccess(ticket: ticket);
      expect(decision.outcome, ArmTicketAccessOutcome.granted);

      final view = armPublicTicketView(ticket);
      // A public URL that resolves to a stack trace is the first support
      // ticket becoming the first leak.
      expect(view.caseIds, isEmpty);
      expect(view.issueId, isNull);
      expect(view.sessionId, isNull);
      // And it does not publish the contact details of whoever wrote in.
      expect(view.reporterContact, isNull);
      expect(view.updates.single.authorLabel, 'Customer');
      // What it does carry is the conversation.
      expect(view.updates.single.body, 'It spins and then nothing happens.');
    });

    test('an allowlisted ticket is not readable on an unproven address', () {
      final ticket = _ticket(allowlist: const <String>['ops@example.com']);

      // Typing an address is not proving it: anybody who can guess a
      // colleague's address would otherwise hold the ticket.
      final typed = armTicketAccess(
        ticket: ticket,
        viewerEmail: 'ops@example.com',
      );
      expect(typed.outcome, ArmTicketAccessOutcome.verificationRequired);

      final proven = armTicketAccess(
        ticket: ticket,
        viewerEmail: 'OPS@example.com',
        viewerVerified: true,
      );
      expect(proven.outcome, ArmTicketAccessOutcome.granted);

      final other = armTicketAccess(
        ticket: ticket,
        viewerEmail: 'stranger@example.com',
        viewerVerified: true,
      );
      expect(other.outcome, ArmTicketAccessOutcome.denied);
      // And the refusal does not say who is on the list.
      expect(other.reason, isNot(contains('ops@example.com')));
    });

    test('the route mints the id and names the author from the caller',
        () async {
      final repository = _TicketRepository();
      final handler = createArmPrivateServiceHandler(
        service: _service(repository),
        authorizer: (_) => const ArmAuthorizedPrincipal(
          actorId: 'platform-runtime',
          actorEmail: 'operator@example.com',
        ),
      );

      final created = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/projects/customer-ops/arm/tickets'),
          headers: const <String, String>{
            'authorization': 'Bearer token',
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, Object?>{
            'title': 'Checkout will not submit',
            'description': 'It spins.',
          }),
        ),
      );
      expect(created.statusCode, 201);
      final Map<String, Object?> body =
          jsonDecode(await created.readAsString()) as Map<String, Object?>;
      final Map<String, Object?> ticket =
          body['ticket']! as Map<String, Object?>;
      final String ticketId = ticket['ticketId']! as String;

      final replied = await handler(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/tickets/$ticketId/updates',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer token',
            'content-type': 'application/json',
          },
          // The body names no author, and could not be believed if it did.
          body: jsonEncode(<String, Object?>{'body': 'Looking at it now.'}),
        ),
      );
      expect(replied.statusCode, 200);
      final Map<String, Object?> updated =
          (jsonDecode(await replied.readAsString())
              as Map<String, Object?>)['ticket']! as Map<String, Object?>;
      final List<Object?> updates = updated['updates']! as List<Object?>;
      final Map<String, Object?> last =
          updates.last as Map<String, Object?>;
      expect(last['authorLabel'], 'operator@example.com');
      expect(last['authorKind'], 'operator');
    });

    test('a stored ticket round-trips through its own codec', () {
      final ticket = _ticket(allowlist: const <String>['ops@example.com']);
      expect(
        decodeArmTicketRecord(encodeArmTicketRecord(ticket), r'$'),
        ticket,
      );
    });
  });
}

const ArmAuthorizedPrincipal _principal = ArmAuthorizedPrincipal(
  actorId: 'platform-runtime',
  actorEmail: 'operator@example.com',
);

ArmPrivateService _service(_TicketRepository repository) {
  int minted = 0;
  return ArmPrivateService(
    repository: repository,
    clock: () => DateTime.utc(2026, 8, 31, 3).add(Duration(minutes: minted)),
    generateId: () => 'id${minted += 1}',
  );
}

ArmTicketRecord _ticket({
  required List<String> allowlist,
  List<String> caseIds = const <String>['case_a'],
}) => ArmTicketRecord(
  ticketId: 'ticket_a',
  title: 'Checkout will not submit',
  description: 'It spins and then nothing happens.',
  status: ArmTicketStatus.open,
  createdAt: DateTime.utc(2026, 8, 31, 3),
  updatedAt: DateTime.utc(2026, 8, 31, 3),
  createdBy: 'citadel_arm_client',
  reporterContact: 'buyer@example.com',
  caseIds: caseIds,
  issueId: 'issue_a',
  sessionId: 'session_a',
  allowlist: allowlist,
  updates: <ArmTicketUpdate>[
    ArmTicketUpdate(
      updateId: 'update_a',
      authorKind: ArmTicketAuthorKind.endUser,
      authorLabel: 'buyer@example.com',
      body: 'It spins and then nothing happens.',
      createdAt: DateTime.utc(2026, 8, 31, 3),
    ),
  ],
);

final class _TicketRepository implements ArmEvidenceRepository {
  final Map<String, ArmTicketRecord> tickets = <String, ArmTicketRecord>{};

  @override
  Future<ArmTicketPageSlice> listTickets({
    required String projectId,
    required ArmTicketQuery query,
  }) async => ArmTicketPageSlice(
    tickets: tickets.values.toList(growable: false),
  );

  @override
  Future<ArmTicketRecord?> getTicket({
    required String projectId,
    required String ticketId,
  }) async => tickets[ticketId];

  @override
  Future<ArmTicketRecord> writeTicket({
    required String projectId,
    required ArmTicketRecord ticket,
  }) async {
    tickets[ticket.ticketId] = ticket;
    return ticket;
  }

  @override
  Future<ArmAlertingConfiguration> readAlerting({
    required String projectId,
  }) async => ArmAlertingConfiguration(projectId: projectId);

  @override
  Future<ArmAlertingConfiguration> writeAlerting({
    required String projectId,
    required ArmAlertingConfiguration configuration,
    required String updatedBy,
  }) async => configuration;

  @override
  Future<ArmCaseDetail?> getCaseDetail({
    required String projectId,
    required String caseId,
  }) async => null;

  @override
  Future<ArmCasePageSlice> listCases({
    required String projectId,
    required ArmCaseQuery query,
  }) async => const ArmCasePageSlice();

  @override
  Future<ArmIssuePageSlice> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  }) async => const ArmIssuePageSlice();

  @override
  Future<ArmCaseRecord?> updateCaseSeverity({
    required String projectId,
    required String caseId,
    required ArmCaseSeverityMutation mutation,
  }) async => null;

  @override
  Future<ArmCaseRecord?> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatusMutation mutation,
  }) async => null;

  @override
  Future<ArmIssueRecord?> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatusMutation mutation,
  }) async => null;

  @override
  Future<ArmIssueRecord?> updateIssueTags({
    required String projectId,
    required String issueId,
    required ArmIssueTagsMutation mutation,
  }) async => null;
}
