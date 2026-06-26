import 'package:arm_console/src/features/auth/domain/auth_models.dart';

abstract interface class AccessRepository {
  Future<UserProjectAccess> getAccessForEmail(String email);
}

class InMemoryAccessRepository implements AccessRepository {
  const InMemoryAccessRepository({
    this.projectRolesByEmail = const <String, Map<String, ProjectAccessRole>>{},
  });

  final Map<String, Map<String, ProjectAccessRole>> projectRolesByEmail;

  @override
  Future<UserProjectAccess> getAccessForEmail(String email) async {
    final String normalizedEmail = normalizeEmail(email);
    return UserProjectAccess(
      email: normalizedEmail,
      projectRoles: Map<String, ProjectAccessRole>.from(
        projectRolesByEmail[normalizedEmail] ??
            const <String, ProjectAccessRole>{},
      ),
    );
  }
}
