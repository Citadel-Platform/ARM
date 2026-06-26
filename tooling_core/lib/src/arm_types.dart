import 'dart:async';

import 'package:meta/meta.dart';

import 'arm_binary_attachment.dart';

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
