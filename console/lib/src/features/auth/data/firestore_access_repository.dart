import 'package:arm_console/src/features/auth/data/access_repository.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreAccessRepository implements AccessRepository {
  FirestoreAccessRepository({
    FirebaseFirestore? firestore,
    this.collectionName = 'console_access',
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String collectionName;

  @override
  Future<UserProjectAccess> getAccessForEmail(String email) async {
    final String normalizedEmail = normalizeEmail(email);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection(collectionName)
        .doc(normalizedEmail)
        .get();

    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final Map<String, ProjectAccessRole> projectRoles = _readProjectRoles(data);

    return UserProjectAccess(
      email: normalizedEmail,
      projectRoles: projectRoles,
    );
  }

  Map<String, ProjectAccessRole> _readProjectRoles(Map<String, dynamic> data) {
    final Set<String> developerProjectIds = _readProjectIds(
      data['developerProjectIds'],
    );
    final Set<String> viewerProjectIds = _readProjectIds(
      data['viewerProjectIds'],
    );
    final Set<String> legacyProjectIds =
        developerProjectIds.isEmpty && viewerProjectIds.isEmpty
        ? _readProjectIds(data['projectIds'] ?? data['projects'])
        : const <String>{};

    final Map<String, ProjectAccessRole> roles = <String, ProjectAccessRole>{};
    for (final String projectId in viewerProjectIds) {
      roles[projectId] = ProjectAccessRole.viewer;
    }
    for (final String projectId in legacyProjectIds) {
      roles[projectId] = ProjectAccessRole.viewer;
    }
    for (final String projectId in developerProjectIds) {
      roles[projectId] = ProjectAccessRole.developer;
    }
    return roles;
  }

  Set<String> _readProjectIds(Object? rawProjectIds) {
    if (rawProjectIds is! List<Object?>) {
      return const <String>{};
    }

    return rawProjectIds
        .whereType<String>()
        .map((String projectId) => projectId.trim())
        .where((String projectId) => projectId.isNotEmpty)
        .toSet();
  }
}
