enum AuthStage {
  bootstrapping,
  signedOut,
  authenticated,
  unauthorized,
  sessionExpired,
}

enum AuthRole { superuser, developer, viewer }

enum ProjectAccessRole { developer, viewer }

enum AuthFailureType { sessionExpired, cancelled, unavailable, unknown }

class AuthGatewayException implements Exception {
  const AuthGatewayException(this.type, [this.message]);

  final AuthFailureType type;
  final String? message;
}

class AuthIdentity {
  const AuthIdentity({
    required this.uid,
    required this.email,
    required this.claims,
  });

  final String uid;
  final String? email;
  final Map<String, Object?> claims;
}

class UserProjectAccess {
  const UserProjectAccess({
    required this.email,
    this.projectRoles = const <String, ProjectAccessRole>{},
  });

  final String email;
  final Map<String, ProjectAccessRole> projectRoles;

  Set<String> get projectIds => projectRoles.keys.toSet();
}

const Set<String> bootstrapSuperuserEmails = <String>{
  'obsidian.infinitum@gmail.com',
};

bool isBootstrapSuperuserEmail(String email) {
  return bootstrapSuperuserEmails.contains(normalizeEmail(email));
}

class AuthSession {
  const AuthSession({
    required this.stage,
    this.email,
    this.role,
    this.allowedProjectIds = const <String>{},
    this.projectRoles = const <String, ProjectAccessRole>{},
    this.isActionInProgress = false,
    this.message,
  });

  const AuthSession.bootstrapping()
    : this(stage: AuthStage.bootstrapping, isActionInProgress: true);

  const AuthSession.signedOut({String? message})
    : this(stage: AuthStage.signedOut, message: message);

  const AuthSession.sessionExpired({String? message})
    : this(stage: AuthStage.sessionExpired, message: message);

  final AuthStage stage;
  final String? email;
  final AuthRole? role;
  final Set<String> allowedProjectIds;
  final Map<String, ProjectAccessRole> projectRoles;
  final bool isActionInProgress;
  final String? message;

  bool get isAuthenticated => stage == AuthStage.authenticated;
  bool get isUnauthorized => stage == AuthStage.unauthorized;
  bool get isSuperuser => role == AuthRole.superuser;

  bool canReadProject(String projectId) {
    if (isSuperuser) {
      return true;
    }
    return allowedProjectIds.contains(projectId);
  }

  bool canWriteProject(String projectId) {
    if (isSuperuser) {
      return true;
    }
    return projectRoles[projectId] == ProjectAccessRole.developer;
  }

  AuthSession copyWith({
    AuthStage? stage,
    String? email,
    AuthRole? role,
    Set<String>? allowedProjectIds,
    Map<String, ProjectAccessRole>? projectRoles,
    bool? isActionInProgress,
    String? message,
    bool clearMessage = false,
  }) {
    return AuthSession(
      stage: stage ?? this.stage,
      email: email ?? this.email,
      role: role ?? this.role,
      allowedProjectIds: allowedProjectIds ?? this.allowedProjectIds,
      projectRoles: projectRoles ?? this.projectRoles,
      isActionInProgress: isActionInProgress ?? this.isActionInProgress,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

String normalizeEmail(String email) => email.trim().toLowerCase();
