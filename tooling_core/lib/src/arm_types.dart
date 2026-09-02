import 'dart:async';

import 'package:meta/meta.dart';

import 'arm_binary_attachment.dart';

/// The Firestore database ARM evidence is written to and read from.
///
/// A database of its own in the client's project, decided 02/09/26. ARM's
/// records used to go into the client's `(default)` database beside their own
/// business collections, where they could collide with a collection the client
/// names — and, more importantly, where no IAM grant could separate Citadel's
/// reach from the client's own data, because Firestore can scope a grant to a
/// database and cannot scope one to a collection.
///
/// The Firebase web and Flutter SDKs talk to `(default)` unless told
/// otherwise, so an application reporting ARM evidence has to say so:
///
/// ```dart
/// FirebaseArmSink(
///   firestore: FirebaseFirestore.instanceFor(
///     app: Firebase.app(),
///     databaseId: armDatabaseId,
///   ),
/// )
/// ```
///
/// Exported as a constant rather than left in a comment because the cost of
/// getting it wrong is silent: an application that writes to `(default)`
/// reports no errors at all, and ARM shows the client a clean dashboard.
const String armDatabaseId = 'citadel-arm';

enum ArmSeverity { info, low, moderate, serious, critical }

extension ArmSeverityX on ArmSeverity {
  String get wireName => name;

  bool get exposesCaseId => index >= ArmSeverity.moderate.index;
}

typedef ArmValueProvider = String? Function();
typedef ArmContextBuilder = FutureOr<Map<String, dynamic>> Function();
typedef ArmSnapshotBuilder = FutureOr<Map<String, dynamic>> Function();
typedef ArmScreenshotCapture = Future<ArmBinaryAttachment?> Function();

@immutable
class ArmBreadcrumb {
  const ArmBreadcrumb({
    required this.message,
    required this.level,
    required this.timestamp,
    this.category,
    this.data,
  });

  final String message;
  final String level;
  final DateTime timestamp;
  final String? category;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'message': message,
      'level': level,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (category != null) 'category': category,
      if (data != null && data!.isNotEmpty) 'data': data,
    };
  }
}
