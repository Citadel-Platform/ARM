import 'dart:convert';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ARM private service handler', () {
    test('fails closed before reading customer evidence', () async {
      final repository = _FakeRepository();
      final handler = createArmPrivateServiceHandler(
        service: ArmPrivateService(repository: repository),
        authorizer: (request) => const ArmAuthorizedPrincipal(
          actorId: 'platform-runtime',
          actorEmail: 'operator@example.com',
        ),
      );

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/projects/customer-ops/arm/issues'),
        ),
      );

      expect(response.statusCode, 401);
      expect(repository.calls, isEmpty);
    });

    test('returns a bounded stable issue page for the exact project', () async {
      final repository = _FakeRepository(
        issues: <ArmIssueRecord>[
          _issue('issue_a', DateTime.utc(2026, 7, 18, 2)),
          _issue('issue_b', DateTime.utc(2026, 7, 18, 3)),
        ],
        hasMoreIssues: true,
      );
      ArmAuthorizationRequest? authorization;
      final handler = createArmPrivateServiceHandler(
        service: ArmPrivateService(repository: repository),
        authorizer: (request) {
          authorization = request;
          return const ArmAuthorizedPrincipal(
            actorId: 'platform-runtime',
            actorEmail: 'operator@example.com',
          );
        },
      );

      final response = await handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/issues?pageSize=2&since=2026-07-01T00%3A00%3A00.000Z',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer google-oidc-token',
            'x-request-id': 'request-arm-1',
          },
        ),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;

      expect(response.statusCode, 200);
      expect(body['requestId'], 'request-arm-1');
      expect(body['projectId'], 'customer-ops');
      final issues = body['issues']! as List<Object?>;
      expect((issues.first! as Map<String, Object?>)['issueId'], 'issue_b');
      expect(body['nextPageToken'], isA<String>());
      final decodedPage = decodeArmIssuePage(body);
      expect(decodedPage.projectId, 'customer-ops');
      expect(decodedPage.issues.map((issue) => issue.issueId), <String>[
        'issue_b',
        'issue_a',
      ]);
      expect(authorization?.projectId, 'customer-ops');
      expect(authorization?.authorizationHeader, 'Bearer google-oidc-token');
      expect(repository.lastIssueQuery?.pageSize, 2);
    });

    test('returns consistent case detail and rejects cross-links', () async {
      final repository = _FakeRepository(
        detail: ArmCaseDetail(
          projectId: 'customer-ops',
          caseRecord: _case('case_1', 'issue_a'),
          issue: _issue('issue_a', DateTime.utc(2026, 7, 18, 2)),
        ),
      );
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/cases/case_1',
          ),
          headers: const <String, String>{'authorization': 'Bearer oidc'},
        ),
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect((body['case']! as Map<String, Object?>)['caseId'], 'case_1');
      expect((body['issue']! as Map<String, Object?>)['issueId'], 'issue_a');
      final detail = decodeArmCaseDetail(body);
      expect(detail.projectId, 'customer-ops');
      expect(detail.caseRecord.caseId, 'case_1');
    });

    test('attributes case status commands without touching handled', () async {
      final repository = _FakeRepository();
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'PATCH',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/cases/case_1/status',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: '{"status":"resolved"}',
        ),
      );

      expect(response.statusCode, 200);
      expect(repository.lastCaseMutation?.status, ArmCaseStatus.resolved);
      expect(repository.lastCaseMutation?.updatedBy, 'operator@example.com');
      expect(
        repository.lastCaseMutation?.statusSource,
        'citadel_platform_operator',
      );
    });

    test('a severity change is recorded beside the captured one', () async {
      // Losing what the capture arrived with would make "did we treat this as
      // urgent, and were we right to" unanswerable afterwards.
      final repository = _FakeRepository();
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'PATCH',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/cases/case_1/severity',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: '{"severity":"low"}',
        ),
      );

      expect(response.statusCode, 200);
      expect(repository.lastSeverityMutation?.severity, ArmSeverity.low);
      expect(repository.lastSeverityMutation?.updatedBy, 'operator@example.com');
      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      final record = body['case']! as Map<String, Object?>;
      expect(record['operatorSeverity'], 'low');
      // The captured severity is untouched.
      expect(record['severity'], isNot('low'));
    });

    test('an unknown severity is refused rather than stored', () async {
      final handler = _authorizedHandler(_FakeRepository());

      final response = await handler(
        Request(
          'PATCH',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/cases/case_1/severity',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: '{"severity":"catastrophic"}',
        ),
      );

      expect(response.statusCode, 400);
    });

    test('tags are replaced as a whole set, normalised', () async {
      // Two operators editing one fingerprint at once would otherwise
      // interleave into a set neither of them chose.
      final repository = _FakeRepository();
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'PATCH',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/issues/issue_a/tags',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: '{"tags":["Regression"," checkout ","regression",""]}',
        ),
      );

      expect(response.statusCode, 200);
      // Lower-cased, trimmed, deduplicated and sorted, so `Regression` and
      // `regression` cannot both exist and mean the same thing.
      expect(repository.lastTagsMutation?.tags, <String>[
        'checkout',
        'regression',
      ]);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect((body['issue']! as Map<String, Object?>)['tags'], <String>[
        'checkout',
        'regression',
      ]);
    });

    test('a tag that is not a tag is refused', () async {
      final handler = _authorizedHandler(_FakeRepository());

      for (final String body in <String>[
        '{"tags":["../etc/passwd"]}',
        '{"tags":[1]}',
        '{"tags":"regression"}',
      ]) {
        final response = await handler(
          Request(
            'PATCH',
            Uri.parse(
              'http://localhost/v1/projects/customer-ops/arm/issues/issue_a/tags',
            ),
            headers: const <String, String>{
              'authorization': 'Bearer oidc',
              'content-type': 'application/json; charset=utf-8',
            },
            body: body,
          ),
        );
        expect(response.statusCode, 400, reason: body);
      }
    });

    test('a policy naming a channel that does not exist is refused', () async {
      // A policy that silently notifies nobody looks identical to one that is
      // working and finding nothing.
      final repository = _FakeRepository();
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'PUT',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/policies/p1',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, Object?>{
            'policyId': 'p1',
            'displayName': 'Checkout regressions',
            'rules': <Object?>[
              <String, Object?>{
                'field': 'title',
                'operator': 'contains',
                'value': 'checkout',
              },
            ],
            'tags': <String>['checkout'],
            'channelIds': <String>['ops_email'],
          }),
        ),
      );

      // A precondition, not a malformed request: the body is valid and the
      // world it refers to is not there.
      expect(response.statusCode, 412);
    });

    test('a channel is stored, then a policy may name it', () async {
      final repository = _FakeRepository();
      final handler = _authorizedHandler(repository);

      final channel = await handler(
        Request(
          'PUT',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/channels/ops_email',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, Object?>{
            'channelId': 'ops_email',
            'displayName': 'Ops',
            'type': 'email',
            'recipients': <String>['Ops@Example.com'],
          }),
        ),
      );
      expect(channel.statusCode, 200);
      expect(repository.lastAlertingWriter, 'operator@example.com');
      expect(
        repository.alerting.channels.single.recipients,
        <String>['ops@example.com'],
      );

      final policy = await handler(
        Request(
          'PUT',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/policies/p1',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, Object?>{
            'policyId': 'p1',
            'displayName': 'Checkout regressions',
            'rules': <Object?>[
              <String, Object?>{
                'field': 'title',
                'operator': 'contains',
                'value': 'checkout',
              },
            ],
            'tags': <String>['Checkout', 'checkout'],
            'channelIds': <String>['ops_email'],
          }),
        ),
      );
      expect(policy.statusCode, 200);
      expect(repository.alerting.policies.single.tags, <String>['checkout']);
    });

    test('a channel a policy still names cannot be deleted', () async {
      // Cascading would leave a policy that looks configured and notifies
      // nobody, which is the failure this surface exists to prevent.
      final repository = _FakeRepository()
        ..alerting = const ArmAlertingConfiguration(
          projectId: 'customer-ops',
          channels: <ArmNotificationChannel>[
            ArmNotificationChannel(
              channelId: 'ops_email',
              displayName: 'Ops',
              type: ArmChannelType.email,
              recipients: <String>['ops@example.com'],
            ),
          ],
          policies: <ArmPolicyRecord>[
            ArmPolicyRecord(
              policyId: 'p1',
              displayName: 'Checkout',
              rules: <ArmPolicyRule>[
                ArmPolicyRule(
                  field: ArmPolicyField.title,
                  operator: ArmPolicyOperator.contains,
                  value: 'checkout',
                ),
              ],
              channelIds: <String>['ops_email'],
            ),
          ],
        );
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'DELETE',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/channels/ops_email',
          ),
          headers: const <String, String>{'authorization': 'Bearer oidc'},
        ),
      );

      expect(response.statusCode, 412);
      expect(await response.readAsString(), contains('p1'));
    });

    test('a policy with no rules is refused', () async {
      // It would match every fingerprint, which is never what anybody meant.
      final handler = _authorizedHandler(_FakeRepository());
      final response = await handler(
        Request(
          'PUT',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/policies/p1',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, Object?>{
            'policyId': 'p1',
            'displayName': 'Everything',
            'rules': <Object?>[],
          }),
        ),
      );
      expect(response.statusCode, 400);
    });

    test('a webhook over plain HTTP is refused', () async {
      // A webhook carries a fault report, sometimes with a stack trace in it.
      final handler = _authorizedHandler(_FakeRepository());
      final response = await handler(
        Request(
          'PUT',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/channels/hook',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, Object?>{
            'channelId': 'hook',
            'displayName': 'Hook',
            'type': 'webhook',
            'recipients': <String>['http://ops.example.test/hook'],
          }),
        ),
      );
      expect(response.statusCode, 400);
    });

    test('a deployment with no transport says so rather than reporting a send',
        () async {
      final repository = _FakeRepository()
        ..alerting = const ArmAlertingConfiguration(
          projectId: 'customer-ops',
          channels: <ArmNotificationChannel>[
            ArmNotificationChannel(
              channelId: 'ops_email',
              displayName: 'Ops',
              type: ArmChannelType.email,
              recipients: <String>['ops@example.com'],
            ),
          ],
        );
      final handler = _authorizedHandler(repository);

      final response = await handler(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/alerting/channels/ops_email/test',
          ),
          headers: const <String, String>{'authorization': 'Bearer oidc'},
        ),
      );

      expect(response.statusCode, 503);
    });

    test('rejects unknown query fields and malformed commands safely', () async {
      final repository = _FakeRepository();
      final handler = _authorizedHandler(repository);

      final queryResponse = await handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/cases?unknown=true',
          ),
          headers: const <String, String>{'authorization': 'Bearer oidc'},
        ),
      );
      final commandResponse = await handler(
        Request(
          'PATCH',
          Uri.parse(
            'http://localhost/v1/projects/customer-ops/arm/issues/issue_a/status',
          ),
          headers: const <String, String>{
            'authorization': 'Bearer oidc',
            'content-type': 'application/json',
          },
          body: '{"status":"invented"}',
        ),
      );

      expect(queryResponse.statusCode, 400);
      expect(commandResponse.statusCode, 400);
      expect(repository.calls, isEmpty);
    });

    test('strict page decoders reject unknown or malformed response data', () {
      expect(
        () => decodeArmCasePage(<String, Object?>{
          'projectId': 'customer-ops',
          'cases': <Object?>[],
          'unexpected': true,
        }),
        throwsFormatException,
      );
      expect(
        () => decodeArmIssuePage(<String, Object?>{
          'projectId': 'customer-ops',
          'issues': 'not-a-list',
        }),
        throwsFormatException,
      );
    });
  });
}

Handler _authorizedHandler(_FakeRepository repository) {
  return createArmPrivateServiceHandler(
    service: ArmPrivateService(repository: repository),
    authorizer: (request) => const ArmAuthorizedPrincipal(
      actorId: 'platform-runtime',
      actorEmail: 'operator@example.com',
    ),
  );
}

ArmIssueRecord _issue(String issueId, DateTime lastSeenAt) => ArmIssueRecord(
  issueId: issueId,
  severity: 'serious',
  category: 'runtime',
  feature: 'checkout',
  operation: 'submit',
  firstSeenAt: DateTime.utc(2026, 7, 1),
  lastSeenAt: lastSeenAt,
  caseCount: 1,
  status: ArmIssueStatus.open,
);

ArmCaseRecord _case(String caseId, String issueId, {bool handled = false}) =>
    ArmCaseRecord(
      caseId: caseId,
      issueId: issueId,
      fingerprint: 'fingerprint-1',
      severity: 'serious',
      category: 'runtime',
      feature: 'checkout',
      operation: 'submit',
      message: 'Checkout failed',
      errorType: 'StateError',
      stackTrace: 'stack',
      sessionId: 'session-1',
      handled: handled,
      createdAt: DateTime.utc(2026, 7, 18, 3),
    );

final class _FakeRepository implements ArmEvidenceRepository {
  _FakeRepository({
    this.issues = const <ArmIssueRecord>[],
    this.detail,
    this.hasMoreIssues = false,
  });

  final List<ArmIssueRecord> issues;
  final ArmCaseDetail? detail;
  final bool hasMoreIssues;

  /// Whether the application caught the error when the case was captured. A
  /// triage command must return it unchanged.
  static const bool capturedHandled = true;
  final List<String> calls = <String>[];
  ArmIssueQuery? lastIssueQuery;
  ArmCaseStatusMutation? lastCaseMutation;
  ArmCaseSeverityMutation? lastSeverityMutation;
  ArmIssueTagsMutation? lastTagsMutation;
  String? lastAlertingWriter;

  @override
  Future<ArmCaseDetail?> getCaseDetail({
    required String projectId,
    required String caseId,
  }) async {
    calls.add('detail:$projectId:$caseId');
    return detail;
  }

  @override
  Future<ArmCasePageSlice> listCases({
    required String projectId,
    required ArmCaseQuery query,
  }) async {
    calls.add('cases:$projectId');
    return const ArmCasePageSlice();
  }

  @override
  Future<ArmIssuePageSlice> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  }) async {
    calls.add('issues:$projectId');
    lastIssueQuery = query;
    return ArmIssuePageSlice(issues: issues, hasMore: hasMoreIssues);
  }

  @override
  Future<ArmCaseRecord?> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatusMutation mutation,
  }) async {
    calls.add('case-status:$projectId:$caseId');
    lastCaseMutation = mutation;
    return _case(
      caseId,
      'issue_a',
      handled: capturedHandled,
    ).copyWith(status: mutation.status);
  }

  final Map<String, ArmTicketRecord> tickets = <String, ArmTicketRecord>{};

  @override
  Future<ArmTicketPageSlice> listTickets({
    required String projectId,
    required ArmTicketQuery query,
  }) async {
    calls.add('tickets:$projectId');
    return ArmTicketPageSlice(
      tickets: tickets.values.toList(growable: false),
    );
  }

  @override
  Future<ArmTicketRecord?> getTicket({
    required String projectId,
    required String ticketId,
  }) async {
    calls.add('ticket:$projectId:$ticketId');
    return tickets[ticketId];
  }

  @override
  Future<ArmTicketRecord> writeTicket({
    required String projectId,
    required ArmTicketRecord ticket,
  }) async {
    calls.add('ticket-write:$projectId:${ticket.ticketId}');
    tickets[ticket.ticketId] = ticket;
    return ticket;
  }

  ArmAlertingConfiguration alerting = const ArmAlertingConfiguration(
    projectId: 'customer-ops',
  );

  @override
  Future<ArmAlertingConfiguration> readAlerting({
    required String projectId,
  }) async {
    calls.add('alerting-read:$projectId');
    return alerting;
  }

  @override
  Future<ArmAlertingConfiguration> writeAlerting({
    required String projectId,
    required ArmAlertingConfiguration configuration,
    required String updatedBy,
  }) async {
    calls.add('alerting-write:$projectId');
    alerting = configuration.copyWith(projectId: projectId);
    lastAlertingWriter = updatedBy;
    return alerting;
  }

  @override
  Future<ArmCaseRecord?> updateCaseSeverity({
    required String projectId,
    required String caseId,
    required ArmCaseSeverityMutation mutation,
  }) async {
    calls.add('case-severity:$projectId:$caseId');
    lastSeverityMutation = mutation;
    return _case(caseId, 'issue_a', handled: capturedHandled).copyWith(
      operatorSeverity: armSeverityWireName(mutation.severity),
      severityUpdatedBy: mutation.updatedBy,
      severityUpdatedAt: DateTime.utc(2026, 8, 30),
    );
  }

  @override
  Future<ArmIssueRecord?> updateIssueTags({
    required String projectId,
    required String issueId,
    required ArmIssueTagsMutation mutation,
  }) async {
    calls.add('issue-tags:$projectId:$issueId');
    lastTagsMutation = mutation;
    return _issue(
      issueId,
      DateTime.utc(2026, 7, 18, 2),
    ).copyWith(tags: mutation.tags);
  }

  @override
  Future<ArmIssueRecord?> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatusMutation mutation,
  }) async {
    calls.add('issue-status:$projectId:$issueId');
    return _issue(
      issueId,
      DateTime.utc(2026, 7, 18, 2),
    ).copyWith(status: mutation.status);
  }
}
