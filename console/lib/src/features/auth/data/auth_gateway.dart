import 'dart:async';

import 'package:arm_console/src/features/auth/domain/auth_models.dart';

abstract interface class AuthGateway {
  bool get canInteractiveSignIn;
  String? get unavailableReason;

  Stream<AuthIdentity?> authStateChanges();
  Future<AuthIdentity?> getCurrentIdentity();
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

class InMemoryAuthGateway implements AuthGateway {
  InMemoryAuthGateway({
    AuthIdentity? initialIdentity,
    this.allowInteractiveSignIn = true,
  }) : _currentIdentity = initialIdentity;

  final bool allowInteractiveSignIn;
  final StreamController<AuthIdentity?> _controller =
      StreamController<AuthIdentity?>.broadcast();
  AuthIdentity? _currentIdentity;

  @override
  bool get canInteractiveSignIn => allowInteractiveSignIn;

  @override
  String? get unavailableReason => allowInteractiveSignIn
      ? null
      : 'Sign-in is unavailable because Firebase credentials are not configured.';

  @override
  Stream<AuthIdentity?> authStateChanges() => _controller.stream;

  @override
  Future<AuthIdentity?> getCurrentIdentity() async => _currentIdentity;

  @override
  Future<void> signInWithGoogle() async {
    if (!allowInteractiveSignIn) {
      throw const AuthGatewayException(
        AuthFailureType.unavailable,
        'Sign-in is unavailable because Firebase credentials are not configured.',
      );
    }

    _currentIdentity = const AuthIdentity(
      uid: 'local-dev-user',
      email: 'developer@local.test',
      claims: <String, Object?>{'arm_console_superuser': true},
    );
    _controller.add(_currentIdentity);
  }

  @override
  Future<void> signOut() async {
    _currentIdentity = null;
    _controller.add(null);
  }

  Future<void> emit(AuthIdentity? identity) async {
    _currentIdentity = identity;
    _controller.add(identity);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
