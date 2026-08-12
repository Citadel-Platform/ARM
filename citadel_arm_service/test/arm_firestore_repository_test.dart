import 'dart:convert';

import 'package:citadel_arm_service/citadel_arm_service.dart';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _registryProjectId = 'citadel-platform';
const String _citadelProjectId = 'axis-education';
const String _customerProjectId = 'luminary-axis-dashboard';

void main() {
  test(
    'routes a registered ARM project to its customer Firestore boundary',
    () async {
      final requests = <String>[];
      final router = FirestoreArmProjectRouter(
        firestoreApi: _api(requests, _registryDocuments()),
        registryProjectId: _registryProjectId,
      );

      final target = await router.resolve(_citadelProjectId);

      expect(target.customerProjectId, _customerProjectId);
      expect(
        target.documentsRoot,
        'projects/$_customerProjectId/databases/(default)/documents',
      );

      await router.resolve(_citadelProjectId);
      expect(
        requests.where((path) => path.contains('platform_projects')).length,
        1,
        reason: 'the registry lookup is cached between requests',
      );
    },
  );

  test('fails closed when ARM is not enabled for the project', () async {
    final router = FirestoreArmProjectRouter(
      firestoreApi: _api(<String>[], _registryDocuments(armEnabled: false)),
      registryProjectId: _registryProjectId,
    );

    await expectLater(
      router.resolve(_citadelProjectId),
      throwsA(
        isA<ArmServiceException>().having(
          (error) => error.code,
          'code',
          ArmServiceErrorCode.failedPrecondition,
        ),
      ),
    );
  });

  test(
    'orders mixed timestamp and string evidence newest first across pages',
    () async {
      final service = ArmPrivateService(repository: _repository(<String>[]));

      final first = await service.listIssues(
        projectId: _citadelProjectId,
        query: const ArmIssueQuery(pageSize: 2),
      );

      expect(
        first.issues.map((issue) => issue.issueId),
        <String>['issue_string_newest', 'issue_timestamp_middle'],
      );
      expect(first.nextPageToken, isNotNull);

      final second = await service.listIssues(
        projectId: _citadelProjectId,
        query: ArmIssueQuery(
          pageSize: 2,
          cursor: decodeArmPageToken(first.nextPageToken!),
        ),
      );

      expect(
        second.issues.map((issue) => issue.issueId),
        <String>['issue_string_oldest'],
      );
      expect(second.nextPageToken, isNull);
    },
  );

  test('skips evidence that cannot be represented instead of failing', () async {
    final service = ArmPrivateService(repository: _repository(<String>[]));

    final page = await service.listCases(
      projectId: _citadelProjectId,
      query: const ArmCaseQuery(),
    );

    expect(page.cases.map((item) => item.caseId), <String>[
      'ARM-20260805-ACAA8AD0',
    ]);
    expect(page.cases.single.status, ArmCaseStatus.newCase);
    expect(page.cases.single.severity, 'moderate');
    expect(page.cases.single.context['method'], 'POST');
  });

  test('writes only the status envelope when a case is resolved', () async {
    final requests = <String>[];
    final service = ArmPrivateService(repository: _repository(requests));

    final updated = await service.updateCaseStatus(
      projectId: _citadelProjectId,
      caseId: 'ARM-20260805-ACAA8AD0',
      status: ArmCaseStatus.resolved,
      principal: const ArmAuthorizedPrincipal(
        actorId: 'firebaseIdToken:uid-1',
        actorEmail: 'Operator@Example.com',
      ),
    );

    expect(updated.status, ArmCaseStatus.resolved);
    expect(
      updated.handled,
      isFalse,
      reason:
          'handled records whether the app caught the error at capture time '
          'and must survive a triage command unchanged',
    );
    final patch = requests.singleWhere((path) => path.startsWith('PATCH'));
    expect(patch, contains('updateMask.fieldPaths=status'));
    expect(patch, contains('currentDocument.exists=true'));
    expect(patch, contains('statusUpdatedBy'));
    expect(
      patch,
      isNot(contains('handled')),
      reason: 'triage must not write the capture-time handled flag',
    );
  });

  test('reports a missing case as not found', () async {
    final service = ArmPrivateService(repository: _repository(<String>[]));

    await expectLater(
      service.updateIssueStatus(
        projectId: _citadelProjectId,
        issueId: 'issue_absent',
        status: ArmIssueStatus.resolved,
        principal: const ArmAuthorizedPrincipal(
          actorId: 'firebaseIdToken:uid-1',
          actorEmail: 'operator@example.com',
        ),
      ),
      throwsA(
        isA<ArmServiceException>().having(
          (error) => error.code,
          'code',
          ArmServiceErrorCode.notFound,
        ),
      ),
    );
  });

  test('fails loudly when the collection outgrows the scan limit', () async {
    final repository = FirestoreArmEvidenceRepository(
      firestoreApi: _api(<String>[], _allDocuments()),
      router: FirestoreArmProjectRouter(
        firestoreApi: _api(<String>[], _allDocuments()),
        registryProjectId: _registryProjectId,
      ),
      maxScanDocuments: 1,
    );

    await expectLater(
      repository.listIssues(
        projectId: _citadelProjectId,
        query: const ArmIssueQuery(),
      ),
      throwsA(
        isA<ArmServiceException>().having(
          (error) => error.code,
          'code',
          ArmServiceErrorCode.failedPrecondition,
        ),
      ),
    );
  });
}

FirestoreArmEvidenceRepository _repository(List<String> requests) {
  final api = _api(requests, _allDocuments());
  return FirestoreArmEvidenceRepository(
    firestoreApi: api,
    router: FirestoreArmProjectRouter(
      firestoreApi: api,
      registryProjectId: _registryProjectId,
    ),
    clock: () => DateTime.utc(2026, 8, 6, 12),
  );
}

/// Serves canned Firestore REST payloads so the repository is exercised through
/// the same client the deployed runtime uses.
firestore_api.FirestoreApi _api(
  List<String> requests,
  Map<String, Map<String, Object?>> documents,
) {
  final store = Map<String, Map<String, Object?>>.from(documents);
  return firestore_api.FirestoreApi(
    MockClient((http.Request request) async {
      final path = Uri.decodeFull(request.url.path);
      requests.add('${request.method} $path?${request.url.query}');
      final name = path.replaceFirst('/v1/', '');

      if (request.method == 'GET' && name.endsWith('/documents/armIssues')) {
        return _json(_listResponse(store, 'armIssues'));
      }
      if (request.method == 'GET' && name.endsWith('/documents/armCases')) {
        return _json(_listResponse(store, 'armCases'));
      }
      if (request.method == 'GET') {
        final document = store[name];
        return document == null ? _notFound() : _json(document);
      }
      if (request.method == 'PATCH') {
        final existing = store[name];
        if (existing == null) {
          return _notFound();
        }
        final patch = jsonDecode(request.body) as Map<String, Object?>;
        final fields = Map<String, Object?>.from(
          existing['fields']! as Map<String, Object?>,
        )..addAll(patch['fields']! as Map<String, Object?>);
        final merged = <String, Object?>{'name': name, 'fields': fields};
        store[name] = merged;
        return _json(merged);
      }
      return _notFound();
    }),
  );
}

Map<String, Object?> _listResponse(
  Map<String, Map<String, Object?>> store,
  String collectionId,
) {
  final documents = store.entries
      .where((entry) => entry.key.contains('/documents/$collectionId/'))
      .map((entry) => entry.value)
      .toList(growable: false);
  return <String, Object?>{'documents': documents};
}

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const <String, String>{'content-type': 'application/json'},
);

http.Response _notFound() => http.Response(
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{'code': 404, 'message': 'not found'},
  }),
  404,
  headers: const <String, String>{'content-type': 'application/json'},
);

Map<String, Map<String, Object?>> _registryDocuments({bool armEnabled = true}) {
  final name =
      'projects/$_registryProjectId/databases/(default)/documents'
      '/platform_projects/$_citadelProjectId';
  return <String, Map<String, Object?>>{
    name: <String, Object?>{
      'name': name,
      'fields': <String, Object?>{
        'status': <String, Object?>{'stringValue': 'active'},
        'firebaseProjectId': <String, Object?>{
          'stringValue': _customerProjectId,
        },
        'offeringScope': <String, Object?>{
          'mapValue': <String, Object?>{
            'fields': <String, Object?>{
              'arm': <String, Object?>{
                'mapValue': <String, Object?>{
                  'fields': <String, Object?>{
                    'enabled': <String, Object?>{'booleanValue': armEnabled},
                  },
                },
              },
            },
          },
        },
      },
    },
  };
}

Map<String, Map<String, Object?>> _allDocuments() {
  const root = 'projects/$_customerProjectId/databases/(default)/documents';
  return <String, Map<String, Object?>>{
    ..._registryDocuments(),
    // Written by the current server sink as an ISO-8601 string.
    '$root/armIssues/issue_string_newest': _issue(
      root: root,
      issueId: 'issue_string_newest',
      lastSeenAt: <String, Object?>{'stringValue': '2026-08-05T08:02:20.297Z'},
    ),
    // Written by the retired browser sink as a real Firestore timestamp.
    '$root/armIssues/issue_timestamp_middle': _issue(
      root: root,
      issueId: 'issue_timestamp_middle',
      lastSeenAt: <String, Object?>{
        'timestampValue': '2026-07-07T02:42:50.813Z',
      },
    ),
    '$root/armIssues/issue_string_oldest': _issue(
      root: root,
      issueId: 'issue_string_oldest',
      lastSeenAt: <String, Object?>{'stringValue': '2026-06-24T13:01:12.300Z'},
    ),
    '$root/armCases/ARM-20260805-ACAA8AD0': <String, Object?>{
      'name': '$root/armCases/ARM-20260805-ACAA8AD0',
      'fields': <String, Object?>{
        'caseId': <String, Object?>{'stringValue': 'ARM-20260805-ACAA8AD0'},
        'issueId': <String, Object?>{'stringValue': 'issue_string_newest'},
        'severity': <String, Object?>{'stringValue': 'moderate'},
        'status': <String, Object?>{'stringValue': 'New'},
        'handled': <String, Object?>{'booleanValue': false},
        'createdAt': <String, Object?>{
          'stringValue': '2026-08-05T08:02:20.297Z',
        },
        'context': <String, Object?>{
          'mapValue': <String, Object?>{
            'fields': <String, Object?>{
              'method': <String, Object?>{'stringValue': 'POST'},
            },
          },
        },
      },
    },
    // No issueId, so it cannot be represented and must be skipped.
    '$root/armCases/ARM-20260101-BROKEN0': <String, Object?>{
      'name': '$root/armCases/ARM-20260101-BROKEN0',
      'fields': <String, Object?>{
        'severity': <String, Object?>{'stringValue': 'moderate'},
        'createdAt': <String, Object?>{
          'stringValue': '2026-01-01T00:00:00.000Z',
        },
      },
    },
  };
}

Map<String, Object?> _issue({
  required String root,
  required String issueId,
  required Map<String, Object?> lastSeenAt,
}) {
  return <String, Object?>{
    'name': '$root/armIssues/$issueId',
    'fields': <String, Object?>{
      'issueId': <String, Object?>{'stringValue': issueId},
      'severity': <String, Object?>{'stringValue': 'serious'},
      'category': <String, Object?>{'stringValue': 'runtime'},
      'feature': <String, Object?>{'stringValue': 'flutter'},
      'operation': <String, Object?>{'stringValue': 'framework_error'},
      'caseCount': <String, Object?>{'integerValue': '1'},
      'firstSeenAt': lastSeenAt,
      'lastSeenAt': lastSeenAt,
    },
  };
}
