import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Commit-safe Firebase options provider.
///
/// Configure values through `--dart-define` (or local tooling that injects
/// these values) and this provider will return `null` when incomplete.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    final String apiKey = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_API_KEY',
    );
    final String appId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_APP_ID',
    );
    final String messagingSenderId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_MESSAGING_SENDER_ID',
    );
    final String projectId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_PROJECT_ID',
    );

    if (_isMissing(apiKey) ||
        _isMissing(appId) ||
        _isMissing(messagingSenderId) ||
        _isMissing(projectId)) {
      return null;
    }

    final String authDomain = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_AUTH_DOMAIN',
    );
    final String databaseURL = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_DATABASE_URL',
    );
    final String storageBucket = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_STORAGE_BUCKET',
    );
    final String measurementId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_MEASUREMENT_ID',
    );
    final String iosBundleId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_IOS_BUNDLE_ID',
    );
    final String androidClientId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_ANDROID_CLIENT_ID',
    );
    final String iosClientId = const String.fromEnvironment(
      'ARM_CONSOLE_FIREBASE_IOS_CLIENT_ID',
    );

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: _optional(authDomain),
      databaseURL: _optional(databaseURL),
      storageBucket: _optional(storageBucket),
      measurementId: kIsWeb ? _optional(measurementId) : null,
      iosBundleId: _optional(iosBundleId),
      androidClientId: _optional(androidClientId),
      iosClientId: _optional(iosClientId),
    );
  }

  static String? _optional(String value) {
    return _isMissing(value) ? null : value;
  }

  static bool _isMissing(String value) => value.trim().isEmpty;
}
