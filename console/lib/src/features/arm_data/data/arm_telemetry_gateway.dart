import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class ArmMonitoredProject {
  const ArmMonitoredProject({
    required this.id,
    required this.name,
    required this.environmentLabel,
    required this.firebaseConfig,
  });

  final String id;
  final String name;
  final String environmentLabel;
  final ProjectFirebaseConfig firebaseConfig;

  String get shellLabel => '$name · $environmentLabel';
}

class ArmIssueDocument {
  const ArmIssueDocument({
    required this.issueId,
    required this.severity,
    required this.category,
    required this.feature,
    required this.operation,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.caseCount,
    required this.firstCaseId,
    required this.lastCaseId,
  });

  final String issueId;
  final String severity;
  final String category;
  final String feature;
  final String operation;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int caseCount;
  final String? firstCaseId;
  final String? lastCaseId;
}

class ArmCaseDocument {
  const ArmCaseDocument({
    required this.caseId,
    required this.issueId,
    required this.fingerprint,
    required this.severity,
    required this.category,
    required this.feature,
    required this.operation,
    required this.message,
    required this.errorType,
    required this.stackTrace,
    required this.sessionId,
    required this.handled,
    required this.context,
    required this.tags,
    required this.breadcrumbs,
    required this.createdAt,
    this.recoverySnapshot,
    this.screenshot,
  });

  final String caseId;
  final String issueId;
  final String fingerprint;
  final String severity;
  final String category;
  final String feature;
  final String operation;
  final String message;
  final String errorType;
  final String stackTrace;
  final String sessionId;
  final bool handled;
  final Map<String, Object?> context;
  final Map<String, Object?> tags;
  final List<Map<String, Object?>> breadcrumbs;
  final Map<String, Object?>? recoverySnapshot;
  final Map<String, Object?>? screenshot;
  final DateTime createdAt;
}

class ArmProjectTelemetry {
  const ArmProjectTelemetry({
    required this.project,
    required this.issues,
    required this.cases,
  });

  final ArmMonitoredProject project;
  final List<ArmIssueDocument> issues;
  final List<ArmCaseDocument> cases;
}

class ArmCaseDetailBundle {
  const ArmCaseDetailBundle({
    required this.project,
    required this.issue,
    required this.caseDocument,
  });

  final ArmMonitoredProject project;
  final ArmIssueDocument issue;
  final ArmCaseDocument caseDocument;
}

class ArmProjectAccessResult {
  const ArmProjectAccessResult({
    required this.project,
    required this.canReadTelemetry,
    this.errorMessage,
  });

  final ArmMonitoredProject project;
  final bool canReadTelemetry;
  final String? errorMessage;
}

abstract interface class ArmTelemetryGateway {
  Future<List<ArmProjectTelemetry>> loadProjectTelemetry({
    required List<ArmMonitoredProject> projects,
    required DateTime issueSince,
    required DateTime caseSince,
  });

  Future<ArmCaseDetailBundle?> loadCaseDetail({
    required List<ArmMonitoredProject> projects,
    required String caseId,
  });

  Future<List<ArmProjectAccessResult>> probeProjectAccess({
    required List<ArmMonitoredProject> projects,
  });
}

class FirebaseArmTelemetryGateway implements ArmTelemetryGateway {
  FirebaseArmTelemetryGateway({
    FirebaseFirestore Function(FirebaseApp app)? firestoreForApp,
  }) : _firestoreForApp =
           firestoreForApp ??
           ((FirebaseApp app) => FirebaseFirestore.instanceFor(app: app));

  final FirebaseFirestore Function(FirebaseApp app) _firestoreForApp;
  final Map<String, Future<FirebaseApp>> _appCache =
      <String, Future<FirebaseApp>>{};

  @override
  Future<List<ArmProjectTelemetry>> loadProjectTelemetry({
    required List<ArmMonitoredProject> projects,
    required DateTime issueSince,
    required DateTime caseSince,
  }) {
    return Future.wait(
      projects.map(
        (ArmMonitoredProject project) =>
            _loadProject(project, issueSince: issueSince, caseSince: caseSince),
      ),
    );
  }

  @override
  Future<ArmCaseDetailBundle?> loadCaseDetail({
    required List<ArmMonitoredProject> projects,
    required String caseId,
  }) async {
    for (final ArmMonitoredProject project in projects) {
      final FirebaseApp app = await _ensureApp(project);
      final FirebaseFirestore firestore = _firestoreForApp(app);
      final DocumentSnapshot<Map<String, dynamic>> caseSnapshot =
          await firestore.collection('armCases').doc(caseId).get();
      if (!caseSnapshot.exists) {
        continue;
      }

      final ArmCaseDocument caseDocument = _caseFromSnapshot(
        caseSnapshot.id,
        caseSnapshot.data() ?? const <String, dynamic>{},
      );
      final DocumentSnapshot<Map<String, dynamic>> issueSnapshot =
          await firestore
              .collection('armIssues')
              .doc(caseDocument.issueId)
              .get();
      if (!issueSnapshot.exists) {
        continue;
      }

      return ArmCaseDetailBundle(
        project: project,
        issue: _issueFromSnapshot(
          issueSnapshot.id,
          issueSnapshot.data() ?? const <String, dynamic>{},
        ),
        caseDocument: caseDocument,
      );
    }
    return null;
  }

  @override
  Future<List<ArmProjectAccessResult>> probeProjectAccess({
    required List<ArmMonitoredProject> projects,
  }) {
    return Future.wait(
      projects.map((ArmMonitoredProject project) async {
        try {
          final FirebaseApp app = await _ensureApp(project);
          final FirebaseFirestore firestore = _firestoreForApp(app);
          await firestore.collection('armIssues').limit(1).get();
          return ArmProjectAccessResult(
            project: project,
            canReadTelemetry: true,
          );
        } on FirebaseException catch (error) {
          return ArmProjectAccessResult(
            project: project,
            canReadTelemetry: false,
            errorMessage: error.message ?? error.code,
          );
        } catch (error) {
          return ArmProjectAccessResult(
            project: project,
            canReadTelemetry: false,
            errorMessage: '$error',
          );
        }
      }),
    );
  }

  Future<ArmProjectTelemetry> _loadProject(
    ArmMonitoredProject project, {
    required DateTime issueSince,
    required DateTime caseSince,
  }) async {
    final FirebaseApp app = await _ensureApp(project);
    final FirebaseFirestore firestore = _firestoreForApp(app);
    final Future<QuerySnapshot<Map<String, dynamic>>> issuesFuture = firestore
        .collection('armIssues')
        .where(
          'lastSeenAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(issueSince),
        )
        .get();
    final Future<QuerySnapshot<Map<String, dynamic>>> casesFuture = firestore
        .collection('armCases')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(caseSince),
        )
        .get();

    final QuerySnapshot<Map<String, dynamic>> issuesSnapshot =
        await issuesFuture;
    final QuerySnapshot<Map<String, dynamic>> casesSnapshot = await casesFuture;

    return ArmProjectTelemetry(
      project: project,
      issues: issuesSnapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                _issueFromSnapshot(doc.id, doc.data()),
          )
          .toList(),
      cases: casesSnapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                _caseFromSnapshot(doc.id, doc.data()),
          )
          .toList(),
    );
  }

  Future<FirebaseApp> _ensureApp(ArmMonitoredProject project) {
    final String cacheKey = _appCacheKey(project);
    return _appCache.putIfAbsent(cacheKey, () async {
      final String appName = _appName(project);
      final FirebaseApp? existing = Firebase.apps
          .cast<FirebaseApp?>()
          .firstWhere(
            (FirebaseApp? app) => app?.name == appName,
            orElse: () => null,
          );
      if (existing != null) {
        return existing;
      }

      return Firebase.initializeApp(
        name: appName,
        options: FirebaseOptions(
          apiKey: project.firebaseConfig.apiKey,
          appId: project.firebaseConfig.appId,
          messagingSenderId: project.firebaseConfig.messagingSenderId,
          projectId: project.firebaseConfig.projectId,
          authDomain: project.firebaseConfig.authDomain,
          databaseURL: project.firebaseConfig.databaseUrl,
          storageBucket: project.firebaseConfig.storageBucket,
          measurementId: project.firebaseConfig.measurementId,
          androidClientId: project.firebaseConfig.androidClientId,
          iosClientId: project.firebaseConfig.iosClientId,
          iosBundleId: project.firebaseConfig.iosBundleId,
        ),
      );
    });
  }

  String _appCacheKey(ArmMonitoredProject project) {
    final ProjectFirebaseConfig config = project.firebaseConfig;
    return [
      project.id,
      config.projectId,
      config.appId,
      config.apiKey,
    ].join('|');
  }

  String _appName(ArmMonitoredProject project) {
    final String rawName =
        'arm-console-${project.id}-${project.firebaseConfig.projectId}-${project.firebaseConfig.appId}';
    return rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
  }
}

bool isRemoteCapableConfig(ProjectFirebaseConfig? config) {
  if (config == null || !config.hasRequiredValues) {
    return false;
  }
  return config.apiKey.startsWith('AIza') && config.appId.contains(':');
}

ArmIssueDocument _issueFromSnapshot(
  String documentId,
  Map<String, dynamic> data,
) {
  return ArmIssueDocument(
    issueId: _readString(data['issueId']) ?? documentId,
    severity: _readString(data['severity']) ?? 'low',
    category: _readString(data['category']) ?? '',
    feature: _readString(data['feature']) ?? '',
    operation: _readString(data['operation']) ?? '',
    firstSeenAt: _readTimestamp(data['firstSeenAt']) ?? DateTime.now(),
    lastSeenAt: _readTimestamp(data['lastSeenAt']) ?? DateTime.now(),
    caseCount: _readInt(data['caseCount']) ?? 0,
    firstCaseId: _readString(data['firstCaseId']),
    lastCaseId: _readString(data['lastCaseId']),
  );
}

ArmCaseDocument _caseFromSnapshot(
  String documentId,
  Map<String, dynamic> data,
) {
  return ArmCaseDocument(
    caseId: _readString(data['caseId']) ?? documentId,
    issueId: _readString(data['issueId']) ?? '',
    fingerprint: _readString(data['fingerprint']) ?? '',
    severity: _readString(data['severity']) ?? 'low',
    category: _readString(data['category']) ?? '',
    feature: _readString(data['feature']) ?? '',
    operation: _readString(data['operation']) ?? '',
    message: _readString(data['message']) ?? '',
    errorType: _readString(data['errorType']) ?? '',
    stackTrace: _readString(data['stackTrace']) ?? '',
    sessionId: _readString(data['sessionId']) ?? '',
    handled: data['handled'] as bool? ?? false,
    context: _readObjectMap(data['context']),
    tags: _readObjectMap(data['tags']),
    breadcrumbs: _readBreadcrumbs(data['breadcrumbs']),
    recoverySnapshot: _readNullableObjectMap(data['recoverySnapshot']),
    screenshot: _readNullableObjectMap(data['screenshot']),
    createdAt: _readTimestamp(data['createdAt']) ?? DateTime.now(),
  );
}

DateTime? _readTimestamp(Object? value) {
  return switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    String isoValue => DateTime.tryParse(isoValue)?.toLocal(),
    _ => null,
  };
}

String? _readString(Object? value) {
  final String text = (value as String? ?? '').trim();
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  return (value as num?)?.toInt();
}

Map<String, Object?> _readObjectMap(Object? value) {
  return _readNullableObjectMap(value) ?? <String, Object?>{};
}

Map<String, Object?>? _readNullableObjectMap(Object? value) {
  final Map<Object?, Object?>? raw = value as Map<Object?, Object?>?;
  if (raw == null) {
    return null;
  }
  return raw.map<String, Object?>(
    (Object? key, Object? item) => MapEntry(key.toString(), item),
  );
}

List<Map<String, Object?>> _readBreadcrumbs(Object? value) {
  final List<Object?> raw = value as List<Object?>? ?? const <Object?>[];
  return raw
      .whereType<Map<Object?, Object?>>()
      .map(
        (Map<Object?, Object?> item) => item.map<String, Object?>(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      )
      .toList();
}
