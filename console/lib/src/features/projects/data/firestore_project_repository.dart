import 'dart:async';

import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'project_repository.dart';

class FirestoreProjectRepository implements ProjectRepository {
  FirestoreProjectRepository({
    FirebaseFirestore? firestore,
    this.projectCollectionName = 'console_projects',
    this.accessCollectionName = 'console_access',
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String projectCollectionName;
  final String accessCollectionName;

  CollectionReference<Map<String, dynamic>> get _projectCollection =>
      _firestore.collection(projectCollectionName);

  CollectionReference<Map<String, dynamic>> get _accessCollection =>
      _firestore.collection(accessCollectionName);

  @override
  Future<List<ConsoleProject>> listProjects({Set<String>? projectIds}) async {
    final List<String>? scopedIds = _normalizedProjectIds(projectIds);
    if (scopedIds != null && scopedIds.isEmpty) {
      return const <ConsoleProject>[];
    }

    if (scopedIds == null) {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _projectCollection.get();
      return _sortedProjects(_projectsFromSnapshot(snapshot));
    }

    final List<ConsoleProject> projects = <ConsoleProject>[];
    for (final List<String> chunk in _chunkProjectIds(scopedIds)) {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _projectQueryForIds(chunk).get();
      projects.addAll(_projectsFromSnapshot(snapshot));
    }
    return _sortedProjects(projects);
  }

  @override
  Stream<List<ConsoleProject>> watchProjects({Set<String>? projectIds}) {
    final List<String>? scopedIds = _normalizedProjectIds(projectIds);
    if (scopedIds != null && scopedIds.isEmpty) {
      return Stream<List<ConsoleProject>>.value(const <ConsoleProject>[]);
    }

    if (scopedIds == null) {
      return _projectCollection.snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> snapshot) =>
            _sortedProjects(_projectsFromSnapshot(snapshot)),
      );
    }

    final List<List<String>> chunks = _chunkProjectIds(scopedIds);
    if (chunks.length == 1) {
      return _projectQueryForIds(chunks.single).snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> snapshot) =>
            _sortedProjects(_projectsFromSnapshot(snapshot)),
      );
    }

    late StreamController<List<ConsoleProject>> controller;
    final Map<int, List<ConsoleProject>> latestProjectsByChunk =
        <int, List<ConsoleProject>>{};
    final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
    subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitCombined() {
      if (latestProjectsByChunk.length != chunks.length) {
        return;
      }
      final List<ConsoleProject> combinedProjects = latestProjectsByChunk.values
          .expand((List<ConsoleProject> projects) => projects)
          .toList();
      controller.add(_sortedProjects(combinedProjects));
    }

    Future<void> startSubscriptions() async {
      for (int index = 0; index < chunks.length; index += 1) {
        final List<String> chunk = chunks[index];
        final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        subscription = _projectQueryForIds(chunk).snapshots().listen((
          QuerySnapshot<Map<String, dynamic>> snapshot,
        ) {
          latestProjectsByChunk[index] = _projectsFromSnapshot(snapshot);
          emitCombined();
        }, onError: controller.addError);
        subscriptions.add(subscription);
      }
    }

    controller = StreamController<List<ConsoleProject>>(
      onListen: () {
        unawaited(startSubscriptions());
      },
      onCancel: () async {
        for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
            subscription
            in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  @override
  Future<void> upsertProject(
    ConsoleProject project, {
    required String actorEmail,
  }) async {
    final DocumentReference<Map<String, dynamic>> projectDocument =
        _projectCollection.doc(project.id);
    final DocumentSnapshot<Map<String, dynamic>> existingSnapshot =
        await projectDocument.get();
    final ConsoleProject? existingProject = existingSnapshot.data() == null
        ? null
        : _projectFromDocument(project.id, existingSnapshot.data()!);

    final DateTime now = DateTime.now();
    final ConsoleProject normalizedProject = project.copyWith(
      createdAt: existingProject?.createdAt ?? now,
      createdBy: existingProject?.createdBy ?? actorEmail,
      updatedAt: now,
      updatedBy: actorEmail,
      developerEmails: normalizedRoleEmails(project.developerEmails),
      viewerEmails: normalizedRoleEmails(project.viewerEmails),
    );

    final List<ConsoleProject> currentProjects = await listProjects();
    final List<ConsoleProject> nextProjects = <ConsoleProject>[
      for (final ConsoleProject item in currentProjects)
        if (item.id != normalizedProject.id) item,
      normalizedProject,
    ];

    final Set<String> impactedEmails = <String>{
      ...?existingProject?.developerEmails,
      ...?existingProject?.viewerEmails,
      ...normalizedProject.developerEmails,
      ...normalizedProject.viewerEmails,
    };
    final Map<String, _ProjectAccessIndex> nextAccessMap = _buildAccessMap(
      nextProjects,
    );

    final WriteBatch batch = _firestore.batch();
    batch.set(projectDocument, _projectToMap(normalizedProject));

    for (final String email in impactedEmails) {
      final _ProjectAccessIndex accessIndex =
          nextAccessMap[email] ?? const _ProjectAccessIndex.empty();
      batch.set(_accessCollection.doc(email), <String, Object?>{
        'email': email,
        'developerProjectIds': accessIndex.sortedDeveloperProjectIds,
        'viewerProjectIds': accessIndex.sortedViewerProjectIds,
        'projectIds': accessIndex.sortedProjectIds,
        'updatedAt': Timestamp.fromDate(now),
        'updatedBy': actorEmail,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Map<String, dynamic> _projectToMap(ConsoleProject project) {
    return <String, dynamic>{
      'name': project.name,
      'environment': project.environment.name,
      'description': project.description,
      'firebase': <String, Object?>{
        'apiKey': project.firebaseConfig.apiKey,
        'appId': project.firebaseConfig.appId,
        'messagingSenderId': project.firebaseConfig.messagingSenderId,
        'projectId': project.firebaseConfig.projectId,
        'authDomain': project.firebaseConfig.authDomain,
        'databaseUrl': project.firebaseConfig.databaseUrl,
        'storageBucket': project.firebaseConfig.storageBucket,
        'measurementId': project.firebaseConfig.measurementId,
        'androidClientId': project.firebaseConfig.androidClientId,
        'iosClientId': project.firebaseConfig.iosClientId,
        'iosBundleId': project.firebaseConfig.iosBundleId,
      },
      'developerEmails': project.developerEmails,
      'viewerEmails': project.viewerEmails,
      'isReadOnlyConsole': project.isReadOnlyConsole,
      'connection': <String, Object?>{
        'status': project.connectionState.status.name,
        'summary': project.connectionState.summary,
        'checkedAt': project.connectionState.checkedAt == null
            ? null
            : Timestamp.fromDate(project.connectionState.checkedAt!),
      },
      'createdAt': project.createdAt == null
          ? null
          : Timestamp.fromDate(project.createdAt!),
      'updatedAt': project.updatedAt == null
          ? null
          : Timestamp.fromDate(project.updatedAt!),
      'createdBy': project.createdBy,
      'updatedBy': project.updatedBy,
    };
  }

  ConsoleProject _projectFromDocument(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final Map<String, dynamic> firebase =
        (data['firebase'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final Map<String, dynamic> connection =
        (data['connection'] as Map<Object?, Object?>?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return ConsoleProject(
      id: documentId,
      name: (data['name'] as String? ?? documentId).trim(),
      environment: ProjectEnvironment.fromStorage(
        data['environment'] as String? ?? ProjectEnvironment.production.name,
      ),
      description: data['description'] as String?,
      firebaseConfig: ProjectFirebaseConfig(
        apiKey: firebase['apiKey'] as String? ?? '',
        appId: firebase['appId'] as String? ?? '',
        messagingSenderId: firebase['messagingSenderId'] as String? ?? '',
        projectId: firebase['projectId'] as String? ?? '',
        authDomain: firebase['authDomain'] as String?,
        databaseUrl: firebase['databaseUrl'] as String?,
        storageBucket: firebase['storageBucket'] as String?,
        measurementId: firebase['measurementId'] as String?,
        androidClientId: firebase['androidClientId'] as String?,
        iosClientId: firebase['iosClientId'] as String?,
        iosBundleId: firebase['iosBundleId'] as String?,
      ),
      developerEmails: normalizedRoleEmails(
        (data['developerEmails'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(),
      ),
      viewerEmails: normalizedRoleEmails(_readViewerEmails(data)),
      isReadOnlyConsole: data['isReadOnlyConsole'] as bool? ?? true,
      connectionState: ProjectConnectionState(
        status: _readConnectionStatus(connection['status'] as String?),
        summary:
            connection['summary'] as String? ??
            ProjectConnectionStatus.unknown.label,
        checkedAt: _readTimestamp(connection['checkedAt']),
      ),
      createdAt: _readTimestamp(data['createdAt']),
      updatedAt: _readTimestamp(data['updatedAt']),
      createdBy: data['createdBy'] as String?,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  ProjectConnectionStatus _readConnectionStatus(String? rawStatus) {
    return ProjectConnectionStatus.values.firstWhere(
      (ProjectConnectionStatus status) => status.name == rawStatus,
      orElse: () => ProjectConnectionStatus.unknown,
    );
  }

  DateTime? _readTimestamp(Object? value) {
    return switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      _ => null,
    };
  }

  List<ConsoleProject> _sortedProjects(List<ConsoleProject> projects) {
    return projects..sort(
      (ConsoleProject left, ConsoleProject right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
  }

  List<String> _readViewerEmails(Map<String, dynamic> data) {
    final List<String> viewerEmails =
        (data['viewerEmails'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList();
    if (viewerEmails.isNotEmpty) {
      return viewerEmails;
    }
    return (data['adminEmails'] as List<Object?>? ?? const <Object?>[])
        .whereType<String>()
        .toList();
  }

  Map<String, _ProjectAccessIndex> _buildAccessMap(
    List<ConsoleProject> projects,
  ) {
    final Map<String, _ProjectAccessIndex> accessMap =
        <String, _ProjectAccessIndex>{};
    for (final ConsoleProject project in projects) {
      for (final String email in project.viewerEmails) {
        accessMap
            .putIfAbsent(email, _ProjectAccessIndex.new)
            .viewerProjectIds
            .add(project.id);
      }
      for (final String email in project.developerEmails) {
        final _ProjectAccessIndex accessIndex = accessMap.putIfAbsent(
          email,
          _ProjectAccessIndex.new,
        );
        accessIndex.developerProjectIds.add(project.id);
        accessIndex.viewerProjectIds.remove(project.id);
      }
    }
    return accessMap;
  }

  Query<Map<String, dynamic>> _projectQueryForIds(List<String> projectIds) {
    return _projectCollection.where(FieldPath.documentId, whereIn: projectIds);
  }

  List<String>? _normalizedProjectIds(Set<String>? projectIds) {
    if (projectIds == null) {
      return null;
    }
    return projectIds
        .map((String id) => id.trim())
        .where((String id) {
          return id.isNotEmpty;
        })
        .toSet()
        .toList()
      ..sort();
  }

  List<List<String>> _chunkProjectIds(List<String> projectIds) {
    final List<List<String>> chunks = <List<String>>[];
    for (int start = 0; start < projectIds.length; start += 10) {
      final int end = (start + 10) > projectIds.length
          ? projectIds.length
          : start + 10;
      chunks.add(projectIds.sublist(start, end));
    }
    return chunks;
  }

  List<ConsoleProject> _projectsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((
      QueryDocumentSnapshot<Map<String, dynamic>> document,
    ) {
      return _projectFromDocument(document.id, document.data());
    }).toList();
  }
}

class _ProjectAccessIndex {
  _ProjectAccessIndex({
    Set<String>? developerProjectIds,
    Set<String>? viewerProjectIds,
  }) : developerProjectIds = developerProjectIds ?? <String>{},
       viewerProjectIds = viewerProjectIds ?? <String>{};

  const _ProjectAccessIndex.empty()
    : developerProjectIds = const <String>{},
      viewerProjectIds = const <String>{};

  final Set<String> developerProjectIds;
  final Set<String> viewerProjectIds;

  List<String> get sortedDeveloperProjectIds =>
      developerProjectIds.toList()..sort();

  List<String> get sortedViewerProjectIds => viewerProjectIds.toList()..sort();

  List<String> get sortedProjectIds {
    final List<String> projectIds = <String>{
      ...developerProjectIds,
      ...viewerProjectIds,
    }.toList()..sort();
    return projectIds;
  }
}
