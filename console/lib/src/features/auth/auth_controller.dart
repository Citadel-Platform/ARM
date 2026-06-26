import 'dart:async';

import 'package:arm_console/src/features/auth/data/access_repository.dart';
import 'package:arm_console/src/features/auth/data/auth_gateway.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.authGateway, required this.accessRepository});

  final AuthGateway authGateway;
  final AccessRepository accessRepository;

  AuthSession _session = const AuthSession.bootstrapping();
  StreamSubscription<AuthIdentity?>? _authSubscription;
  bool _started = false;

  AuthSession get session => _session;
  bool get canInteractiveSignIn => authGateway.canInteractiveSignIn;
  String? get signInUnavailableReason => authGateway.unavailableReason;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    _authSubscription = authGateway.authStateChanges().listen(
      (AuthIdentity? identity) {
        unawaited(_handleIdentityChanged(identity));
      },
      onError: (Object error, StackTrace stackTrace) {
        _applyAuthError(error);
      },
    );

    try {
      final AuthIdentity? currentIdentity = await authGateway
          .getCurrentIdentity();
      await _handleIdentityChanged(currentIdentity);
    } on Object catch (error) {
      _applyAuthError(error);
    }
  }

  Future<void> signInWithGoogle() async {
    _setSession(
      _session.copyWith(isActionInProgress: true, clearMessage: true),
    );
    try {
      await authGateway.signInWithGoogle();
    } on Object catch (error) {
      _setSession(
        _session.copyWith(
          isActionInProgress: false,
          message: _errorMessage(error),
          stage: _stageForError(error),
        ),
      );
    }
  }

  Future<void> signOut() async {
    _setSession(
      _session.copyWith(isActionInProgress: true, clearMessage: true),
    );

    try {
      await authGateway.signOut();
      _setSession(const AuthSession.signedOut());
    } on Object catch (error) {
      _setSession(
        _session.copyWith(
          isActionInProgress: false,
          stage: _stageForError(error),
          message: _errorMessage(error),
        ),
      );
    }
  }

  Future<void> _resolveIdentity(AuthIdentity? identity) async {
    if (identity == null) {
      _setSession(const AuthSession.signedOut());
      return;
    }

    final String normalizedEmail = normalizeEmail(identity.email ?? '');
    if (normalizedEmail.isEmpty) {
      _setSession(
        const AuthSession(
          stage: AuthStage.unauthorized,
          message: 'Signed-in account has no email and cannot be authorized.',
        ),
      );
      return;
    }

    if (_isSuperuser(identity.claims) ||
        isBootstrapSuperuserEmail(normalizedEmail)) {
      _setSession(
        AuthSession(
          stage: AuthStage.authenticated,
          email: normalizedEmail,
          role: AuthRole.superuser,
          isActionInProgress: false,
        ),
      );
      return;
    }

    final UserProjectAccess access = await accessRepository.getAccessForEmail(
      normalizedEmail,
    );

    if (access.projectRoles.isEmpty) {
      _setSession(
        AuthSession(
          stage: AuthStage.unauthorized,
          email: normalizedEmail,
          message:
              'Your account is signed in but is not assigned to any developer or viewer project scope.',
        ),
      );
      return;
    }

    _setSession(
      AuthSession(
        stage: AuthStage.authenticated,
        email: normalizedEmail,
        role: _roleForProjectAccess(access),
        allowedProjectIds: access.projectIds,
        projectRoles: access.projectRoles,
      ),
    );
  }

  Future<void> _handleIdentityChanged(AuthIdentity? identity) async {
    try {
      await _resolveIdentity(identity);
    } on Object catch (error) {
      await _recoverFromIdentityResolutionFailure(identity, error);
    }
  }

  Future<void> _recoverFromIdentityResolutionFailure(
    AuthIdentity? identity,
    Object error,
  ) async {
    if (identity != null) {
      try {
        await authGateway.signOut();
      } on Object {
        // Preserve the original failure as the user-facing error.
      }
    }

    _applyAuthError(error);
  }

  void _applyAuthError(Object error) {
    _setSession(
      AuthSession(stage: _stageForError(error), message: _errorMessage(error)),
    );
  }

  AuthStage _stageForError(Object error) {
    if (error case final AuthGatewayException exception) {
      if (exception.type == AuthFailureType.sessionExpired) {
        return AuthStage.sessionExpired;
      }
      return AuthStage.signedOut;
    }
    if (error case FirebaseException(plugin: 'cloud_firestore')) {
      return AuthStage.signedOut;
    }
    return AuthStage.signedOut;
  }

  String _errorMessage(Object error) {
    return switch (error) {
      AuthGatewayException(:final String? message) =>
        message ?? 'Authentication failed.',
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable') =>
        'Signed in successfully, but the console could not reach Firestore to load your access scope. Check the Firestore database and your network access, then try again.',
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied') =>
        'Signed in successfully, but Firestore denied the console access lookup. Verify the console Firestore rules and your access mapping, then try again.',
      FirebaseException(plugin: 'cloud_firestore') =>
        'Signed in successfully, but the console could not load your access scope from Firestore.',
      _ => 'Authentication failed.',
    };
  }

  AuthRole _roleForProjectAccess(UserProjectAccess access) {
    final bool hasDeveloperScope = access.projectRoles.values.any(
      (ProjectAccessRole role) => role == ProjectAccessRole.developer,
    );
    return hasDeveloperScope ? AuthRole.developer : AuthRole.viewer;
  }

  bool _isSuperuser(Map<String, Object?> claims) {
    const List<String> claimKeys = <String>[
      'arm_console_superuser',
      'armConsoleSuperuser',
      'superuser',
    ];
    for (final String claimKey in claimKeys) {
      if (_asBool(claims[claimKey])) {
        return true;
      }
    }
    return false;
  }

  bool _asBool(Object? value) {
    return switch (value) {
      bool flag => flag,
      num number => number != 0,
      String string => string.toLowerCase() == 'true' || string == '1',
      _ => false,
    };
  }

  void _setSession(AuthSession nextSession) {
    _session = nextSession;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
