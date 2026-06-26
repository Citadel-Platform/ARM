import 'package:arm_console/src/features/auth/domain/auth_models.dart';

enum ProjectEnvironment {
  production('Production'),
  staging('Staging'),
  development('Development'),
  sandbox('Sandbox');

  const ProjectEnvironment(this.label);

  final String label;

  static ProjectEnvironment fromStorage(String value) {
    return ProjectEnvironment.values.firstWhere(
      (ProjectEnvironment environment) => environment.name == value,
      orElse: () => ProjectEnvironment.production,
    );
  }
}

enum ProjectConnectionStatus { unknown, healthy, warning, failed }

extension ProjectConnectionStatusLabel on ProjectConnectionStatus {
  String get label {
    return switch (this) {
      ProjectConnectionStatus.unknown => 'Needs validation',
      ProjectConnectionStatus.healthy => 'Validated',
      ProjectConnectionStatus.warning => 'Validated with warnings',
      ProjectConnectionStatus.failed => 'Validation failed',
    };
  }
}

enum ProjectValidationCheckStatus { success, warning, failure }

extension ProjectValidationCheckStatusLabel on ProjectValidationCheckStatus {
  String get label {
    return switch (this) {
      ProjectValidationCheckStatus.success => 'Passed',
      ProjectValidationCheckStatus.warning => 'Warning',
      ProjectValidationCheckStatus.failure => 'Failed',
    };
  }
}

class ProjectFirebaseConfig {
  const ProjectFirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.authDomain,
    this.databaseUrl,
    this.storageBucket,
    this.measurementId,
    this.androidClientId,
    this.iosClientId,
    this.iosBundleId,
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? authDomain;
  final String? databaseUrl;
  final String? storageBucket;
  final String? measurementId;
  final String? androidClientId;
  final String? iosClientId;
  final String? iosBundleId;

  bool get hasRequiredValues {
    return apiKey.trim().isNotEmpty &&
        appId.trim().isNotEmpty &&
        messagingSenderId.trim().isNotEmpty &&
        projectId.trim().isNotEmpty;
  }

  ProjectFirebaseConfig copyWith({
    String? apiKey,
    String? appId,
    String? messagingSenderId,
    String? projectId,
    String? authDomain,
    String? databaseUrl,
    String? storageBucket,
    String? measurementId,
    String? androidClientId,
    String? iosClientId,
    String? iosBundleId,
  }) {
    return ProjectFirebaseConfig(
      apiKey: apiKey ?? this.apiKey,
      appId: appId ?? this.appId,
      messagingSenderId: messagingSenderId ?? this.messagingSenderId,
      projectId: projectId ?? this.projectId,
      authDomain: authDomain ?? this.authDomain,
      databaseUrl: databaseUrl ?? this.databaseUrl,
      storageBucket: storageBucket ?? this.storageBucket,
      measurementId: measurementId ?? this.measurementId,
      androidClientId: androidClientId ?? this.androidClientId,
      iosClientId: iosClientId ?? this.iosClientId,
      iosBundleId: iosBundleId ?? this.iosBundleId,
    );
  }
}

class ProjectConnectionState {
  const ProjectConnectionState({
    required this.status,
    required this.summary,
    required this.checkedAt,
  });

  const ProjectConnectionState.unknown()
    : status = ProjectConnectionStatus.unknown,
      summary = 'Run validation before saving monitored-project access.',
      checkedAt = null;

  final ProjectConnectionStatus status;
  final String summary;
  final DateTime? checkedAt;

  ProjectConnectionState copyWith({
    ProjectConnectionStatus? status,
    String? summary,
    DateTime? checkedAt,
  }) {
    return ProjectConnectionState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }
}

class ProjectValidationCheck {
  const ProjectValidationCheck({
    required this.label,
    required this.status,
    required this.message,
  });

  final String label;
  final ProjectValidationCheckStatus status;
  final String message;
}

class ProjectValidationResult {
  const ProjectValidationResult({
    required this.status,
    required this.summary,
    required this.checkedAt,
    required this.checks,
  });

  final ProjectConnectionStatus status;
  final String summary;
  final DateTime checkedAt;
  final List<ProjectValidationCheck> checks;

  bool get isFailure => status == ProjectConnectionStatus.failed;

  ProjectConnectionState get connectionState {
    return ProjectConnectionState(
      status: status,
      summary: summary,
      checkedAt: checkedAt,
    );
  }

  static ProjectValidationResult fromFormErrors(List<String> messages) {
    final DateTime checkedAt = DateTime.now();
    return ProjectValidationResult(
      status: ProjectConnectionStatus.failed,
      summary: 'Complete the required project details before validation.',
      checkedAt: checkedAt,
      checks: messages
          .map(
            (String message) => ProjectValidationCheck(
              label: 'Project form',
              status: ProjectValidationCheckStatus.failure,
              message: message,
            ),
          )
          .toList(),
    );
  }
}

class ConsoleProject {
  const ConsoleProject({
    required this.id,
    required this.name,
    required this.environment,
    required this.firebaseConfig,
    required this.developerEmails,
    required this.viewerEmails,
    required this.isReadOnlyConsole,
    required this.connectionState,
    this.description,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final String id;
  final String name;
  final ProjectEnvironment environment;
  final String? description;
  final ProjectFirebaseConfig firebaseConfig;
  final List<String> developerEmails;
  final List<String> viewerEmails;
  final bool isReadOnlyConsole;
  final ProjectConnectionState connectionState;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  String get environmentLabel => environment.label;

  String get scopeLabel {
    if (developerEmails.isEmpty && viewerEmails.isEmpty) {
      return 'Superuser only';
    }
    final List<String> parts = <String>[];
    if (developerEmails.isNotEmpty) {
      parts.add(
        '${developerEmails.length} developer${developerEmails.length == 1 ? '' : 's'}',
      );
    }
    if (viewerEmails.isNotEmpty) {
      parts.add(
        '${viewerEmails.length} viewer${viewerEmails.length == 1 ? '' : 's'}',
      );
    }
    return parts.join(' · ');
  }

  String get shellLabel => '$name · ${environment.label}';

  ConsoleProject copyWith({
    String? id,
    String? name,
    ProjectEnvironment? environment,
    String? description,
    ProjectFirebaseConfig? firebaseConfig,
    List<String>? developerEmails,
    List<String>? viewerEmails,
    bool? isReadOnlyConsole,
    ProjectConnectionState? connectionState,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
  }) {
    return ConsoleProject(
      id: id ?? this.id,
      name: name ?? this.name,
      environment: environment ?? this.environment,
      description: description ?? this.description,
      firebaseConfig: firebaseConfig ?? this.firebaseConfig,
      developerEmails: developerEmails ?? this.developerEmails,
      viewerEmails: viewerEmails ?? this.viewerEmails,
      isReadOnlyConsole: isReadOnlyConsole ?? this.isReadOnlyConsole,
      connectionState: connectionState ?? this.connectionState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

class ProjectDraft {
  const ProjectDraft({
    required this.id,
    required this.name,
    required this.environment,
    required this.description,
    required this.firebaseConfig,
    required this.developerEmails,
    required this.viewerEmails,
  });

  final String id;
  final String name;
  final ProjectEnvironment environment;
  final String description;
  final ProjectFirebaseConfig firebaseConfig;
  final List<String> developerEmails;
  final List<String> viewerEmails;

  factory ProjectDraft.empty() {
    return ProjectDraft(
      id: '',
      name: '',
      environment: ProjectEnvironment.production,
      description: '',
      firebaseConfig: const ProjectFirebaseConfig(
        apiKey: '',
        appId: '',
        messagingSenderId: '',
        projectId: '',
      ),
      developerEmails: const <String>[],
      viewerEmails: const <String>[],
    );
  }

  factory ProjectDraft.fromProject(ConsoleProject project) {
    return ProjectDraft(
      id: project.id,
      name: project.name,
      environment: project.environment,
      description: project.description ?? '',
      firebaseConfig: project.firebaseConfig,
      developerEmails: project.developerEmails,
      viewerEmails: project.viewerEmails,
    );
  }

  List<String> validationErrors() {
    final List<String> errors = <String>[];
    final String normalizedId = normalizeProjectId(id);
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      errors.add('Project name is required.');
    }
    if (normalizedId.isEmpty) {
      errors.add('Project id is required.');
    } else if (!_projectIdPattern.hasMatch(normalizedId)) {
      errors.add(
        'Project id must use lowercase letters, digits, and hyphens only.',
      );
    }
    if (!firebaseConfig.hasRequiredValues) {
      errors.add(
        'Firebase API key, app id, messaging sender id, and project id are required.',
      );
    }
    final Set<String> seenEmails = <String>{};
    _validateRoleEmails(
      label: 'developer',
      emails: developerEmails,
      errors: errors,
      seenEmails: seenEmails,
    );
    _validateRoleEmails(
      label: 'viewer',
      emails: viewerEmails,
      errors: errors,
      seenEmails: seenEmails,
    );
    return errors;
  }

  String get validationSignature {
    return <Object?>[
      normalizeProjectId(id),
      name.trim(),
      environment.name,
      description.trim(),
      firebaseConfig.apiKey.trim(),
      firebaseConfig.appId.trim(),
      firebaseConfig.messagingSenderId.trim(),
      firebaseConfig.projectId.trim(),
      firebaseConfig.authDomain?.trim(),
      firebaseConfig.databaseUrl?.trim(),
      firebaseConfig.storageBucket?.trim(),
      firebaseConfig.measurementId?.trim(),
      firebaseConfig.androidClientId?.trim(),
      firebaseConfig.iosClientId?.trim(),
      firebaseConfig.iosBundleId?.trim(),
      ...normalizedRoleEmails(developerEmails),
      ...normalizedRoleEmails(viewerEmails),
    ].join('|');
  }

  ConsoleProject toProject({
    required ProjectConnectionState connectionState,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
  }) {
    return ConsoleProject(
      id: normalizeProjectId(id),
      name: name.trim(),
      environment: environment,
      description: _optional(description),
      firebaseConfig: ProjectFirebaseConfig(
        apiKey: firebaseConfig.apiKey.trim(),
        appId: firebaseConfig.appId.trim(),
        messagingSenderId: firebaseConfig.messagingSenderId.trim(),
        projectId: firebaseConfig.projectId.trim(),
        authDomain: _optional(firebaseConfig.authDomain),
        databaseUrl: _optional(firebaseConfig.databaseUrl),
        storageBucket: _optional(firebaseConfig.storageBucket),
        measurementId: _optional(firebaseConfig.measurementId),
        androidClientId: _optional(firebaseConfig.androidClientId),
        iosClientId: _optional(firebaseConfig.iosClientId),
        iosBundleId: _optional(firebaseConfig.iosBundleId),
      ),
      developerEmails: normalizedRoleEmails(developerEmails),
      viewerEmails: normalizedRoleEmails(viewerEmails),
      isReadOnlyConsole: true,
      connectionState: connectionState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }
}

void _validateRoleEmails({
  required String label,
  required List<String> emails,
  required List<String> errors,
  required Set<String> seenEmails,
}) {
  for (final String email in emails) {
    final String normalizedEmail = normalizeEmail(email);
    if (!_emailPattern.hasMatch(normalizedEmail)) {
      errors.add('Invalid $label email: $email');
      continue;
    }
    if (!seenEmails.add(normalizedEmail)) {
      errors.add('Duplicate access email: $normalizedEmail');
    }
  }
}

List<String> normalizedRoleEmails(List<String> emails) {
  final Set<String> normalized = <String>{};
  for (final String email in emails) {
    final String normalizedEmail = normalizeEmail(email);
    if (normalizedEmail.isNotEmpty) {
      normalized.add(normalizedEmail);
    }
  }
  final List<String> sorted = normalized.toList()..sort();
  return sorted;
}

String normalizeProjectId(String value) {
  final String lowerCased = value.trim().toLowerCase();
  final String slug = lowerCased
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug;
}

final RegExp _projectIdPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _optional(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
