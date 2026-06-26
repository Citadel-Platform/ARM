import 'dart:async';

import 'package:arm_console/src/features/auth/data/auth_gateway.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  @override
  bool get canInteractiveSignIn => true;

  @override
  String? get unavailableReason => null;

  @override
  Stream<AuthIdentity?> authStateChanges() {
    return _firebaseAuth.idTokenChanges().asyncMap(_mapUser);
  }

  @override
  Future<AuthIdentity?> getCurrentIdentity() async {
    return _mapUser(_firebaseAuth.currentUser);
  }

  @override
  Future<void> signInWithGoogle() async {
    final GoogleAuthProvider provider = GoogleAuthProvider()
      ..setCustomParameters(<String, String>{'prompt': 'select_account'});

    try {
      if (kIsWeb) {
        await _firebaseAuth.signInWithPopup(provider);
        return;
      }

      await _firebaseAuth.signInWithProvider(provider);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    } on UnsupportedError {
      throw const AuthGatewayException(
        AuthFailureType.unavailable,
        'Google sign-in is unsupported on this platform.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<AuthIdentity?> _mapUser(User? user) async {
    if (user == null) {
      return null;
    }

    try {
      final IdTokenResult tokenResult = await user.getIdTokenResult();
      return AuthIdentity(
        uid: user.uid,
        email: user.email,
        claims: tokenResult.claims ?? const <String, Object?>{},
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  AuthGatewayException _mapAuthError(FirebaseAuthException error) {
    if (_isSessionExpiredCode(error.code)) {
      return AuthGatewayException(
        AuthFailureType.sessionExpired,
        error.message ?? 'The current auth session has expired.',
      );
    }

    if (error.code == 'popup-closed-by-user' ||
        error.code == 'web-context-cancelled') {
      return AuthGatewayException(
        AuthFailureType.cancelled,
        error.message ?? 'Sign-in was cancelled.',
      );
    }

    return AuthGatewayException(
      AuthFailureType.unknown,
      error.message ?? 'Authentication failed.',
    );
  }

  bool _isSessionExpiredCode(String code) {
    return code == 'user-token-expired' ||
        code == 'invalid-user-token' ||
        code == 'user-disabled' ||
        code == 'requires-recent-login';
  }
}
