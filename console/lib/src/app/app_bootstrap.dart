import 'package:arm_console/firebase_options.dart';
import 'package:arm_console/src/features/auth/auth_controller.dart';
import 'package:arm_console/src/features/auth/data/access_repository.dart';
import 'package:arm_console/src/features/auth/data/auth_gateway.dart';
import 'package:arm_console/src/features/auth/data/firebase_auth_gateway.dart';
import 'package:arm_console/src/features/auth/data/firestore_access_repository.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:arm_console/src/features/projects/data/firestore_project_repository.dart';
import 'package:arm_console/src/features/projects/data/project_repository.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_connection_validator.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AppBootstrapper {
  const AppBootstrapper({
    this.firebaseOptions,
    this.enableLocalDevSession = false,
  });

  final FirebaseOptions? firebaseOptions;
  final bool enableLocalDevSession;

  Future<AuthController> createAuthController() async {
    final FirebaseOptions? options =
        firebaseOptions ?? DefaultFirebaseOptions.currentPlatform;

    if (options == null) {
      return _localController();
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }

      return AuthController(
        authGateway: FirebaseAuthGateway(),
        accessRepository: FirestoreAccessRepository(),
      );
    } on FirebaseException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_bootstrap',
          context: ErrorDescription(
            'while initializing Firebase auth bootstrap',
          ),
        ),
      );
      return _localController();
    }
  }

  Future<ProjectController> createProjectController(
    AuthController authController,
  ) async {
    if (Firebase.apps.isEmpty) {
      return _localProjectController(authController);
    }

    return ProjectController(
      authController: authController,
      projectRepository: FirestoreProjectRepository(),
      connectionValidator: const FirebaseProjectConnectionValidator(),
    );
  }

  AuthController _localController() {
    return AuthController(
      authGateway: InMemoryAuthGateway(
        initialIdentity: enableLocalDevSession
            ? AuthIdentity(
                uid: 'local-dev-preview',
                email: 'dev@local.test',
                claims: <String, Object?>{'arm_console_superuser': true},
              )
            : null,
        allowInteractiveSignIn: enableLocalDevSession,
      ),
      accessRepository: const InMemoryAccessRepository(),
    );
  }

  Future<ProjectController> _localProjectController(
    AuthController authController,
  ) async {
    return ProjectController(
      authController: authController,
      projectRepository: InMemoryProjectRepository(
        initialProjects: _fallbackLocalProjects,
      ),
      connectionValidator: const InMemoryProjectConnectionValidator(),
    );
  }
}

const List<ConsoleProject> _fallbackLocalProjects = <ConsoleProject>[
  ConsoleProject(
    id: 'core-platform',
    name: 'Citadel Platform Ops',
    environment: ProjectEnvironment.production,
    description: 'Shared auth, registry, and operator controls.',
    firebaseConfig: ProjectFirebaseConfig(
      apiKey: 'preview-api-key',
      appId: 'preview-app-id',
      messagingSenderId: 'preview-sender-id',
      projectId: 'citadel-platform',
      storageBucket: 'citadel-platform.appspot.com',
    ),
    developerEmails: <String>['lead@example.com'],
    viewerEmails: <String>['ops@example.com'],
    isReadOnlyConsole: true,
    connectionState: ProjectConnectionState(
      status: ProjectConnectionStatus.warning,
      summary:
          'Local preview data is seeded for UI iteration and does not represent a remote validation result.',
      checkedAt: null,
    ),
  ),
  ConsoleProject(
    id: 'customer-ops',
    name: 'Customer Operations',
    environment: ProjectEnvironment.production,
    description: 'Live tenant support and telemetry triage.',
    firebaseConfig: ProjectFirebaseConfig(
      apiKey: 'preview-api-key',
      appId: 'preview-app-id',
      messagingSenderId: 'preview-sender-id',
      projectId: 'citadel-customer-ops',
    ),
    developerEmails: <String>['portal-admin@example.com'],
    viewerEmails: <String>['support@example.com'],
    isReadOnlyConsole: true,
    connectionState: ProjectConnectionState(
      status: ProjectConnectionStatus.healthy,
      summary: 'Preview entry marked healthy for shell and table states.',
      checkedAt: null,
    ),
  ),
  ConsoleProject(
    id: 'innovation-lab',
    name: 'Innovation Lab',
    environment: ProjectEnvironment.sandbox,
    description: 'Product incubation and internal previews.',
    firebaseConfig: ProjectFirebaseConfig(
      apiKey: 'preview-api-key',
      appId: 'preview-app-id',
      messagingSenderId: 'preview-sender-id',
      projectId: 'citadel-innovation-lab',
    ),
    developerEmails: <String>[],
    viewerEmails: <String>[],
    isReadOnlyConsole: true,
    connectionState: ProjectConnectionState.unknown(),
  ),
];
