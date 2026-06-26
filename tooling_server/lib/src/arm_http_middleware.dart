import 'dart:async';
import 'dart:io';

import 'package:arm_tooling_core/arm_tooling_core.dart';

import 'arm_request_context.dart';
import 'arm_server.dart';

class ArmHttpMiddleware {
  const ArmHttpMiddleware._();

  static Future<T> wrap<T>({
    required ArmServer server,
    required HttpRequest request,
    required String feature,
    required String operation,
    required Future<T> Function() action,
    ArmSeverity severity = ArmSeverity.serious,
    String category = 'request',
    Map<String, dynamic>? tags,
    Map<String, dynamic>? context,
    Map<String, dynamic>? recoverySnapshot,
    String? userId,
    String? userEmail,
    String? authSubject,
    String? requestId,
    String? correlationId,
    String? traceId,
    String? spanId,
    FutureOr<void> Function(ArmCaptureResult result)? onReported,
  }) async {
    final requestContext = buildArmRequestContext(
      request,
      userId: userId,
      userEmail: userEmail,
      authSubject: authSubject,
      requestId: requestId,
      correlationId: correlationId,
      traceId: traceId,
      spanId: spanId,
      extra: context,
    );

    return server.runTracked(
      feature: feature,
      operation: operation,
      action: action,
      severity: severity,
      category: category,
      tags: tags,
      context: requestContext,
      recoverySnapshot: recoverySnapshot,
      onReported: onReported,
    );
  }
}
