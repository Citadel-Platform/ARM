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

    test('attributes case status commands and derives handled state', () async {
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
      expect(repository.lastCaseMutation?.handled, isTrue);
      expect(repository.lastCaseMutation?.updatedBy, 'operator@example.com');
      expect(
        repository.lastCaseMutation?.statusSource,
        'citadel_platform_operator',
      );
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
  final List<String> calls = <String>[];
  ArmIssueQuery? lastIssueQuery;
  ArmCaseStatusMutation? lastCaseMutation;

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
      handled: mutation.handled,
    ).copyWith(status: mutation.status);
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
