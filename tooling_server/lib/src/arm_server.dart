import 'dart:async';

import 'package:arm_tooling_core/arm_tooling_core.dart';

import 'arm_server_error.dart';

class ArmServer {
  ArmServer({
    required ArmSink sink,
    required this.appId,
    required this.environment,
    this.appVersion,
    this.buildNumber,
    this.releaseChannel,
    this.contextBuilder,
    this.caseIdExposureThreshold = ArmSeverity.moderate,
    this.runtime = 'server',
  }) : _sink = sink,
       _sessionId = buildArmSessionId(appId, prefix: 'server-session');

  final ArmSink _sink;
  final String appId;
  final String environment;
  final String? appVersion;
  final String? buildNumber;
  final String? releaseChannel;
  final ArmContextBuilder? contextBuilder;
  final ArmSeverity caseIdExposureThreshold;
  final String runtime;
  final String _sessionId;

  String get sessionId => _sessionId;

  Future<ArmCaptureResult> captureException({
    required Object error,
    required StackTrace stackTrace,
    required String feature,
    required String operation,
    ArmSeverity severity = ArmSeverity.low,
    String category = 'server',
    Map<String, dynamic>? tags,
    Map<String, dynamic>? context,
    Map<String, dynamic>? recoverySnapshot,
    bool handled = false,
  }) async {
    final errorDetails = describeArmServerError(error);
    final fingerprint = buildArmFingerprint(
      feature: feature,
      operation: operation,
      errorType: errorDetails.name,
      message: errorDetails.message,
      stackTrace: stackTrace,
    );
    final request = ArmCaptureRequest(
      severity: severity,
      category: category,
      feature: feature,
      operation: operation,
      message: errorDetails.message,
      errorType: errorDetails.name,
      errorName: errorDetails.name,
      errorData: errorDetails.data.isEmpty ? null : errorDetails.data,
      stackTrace: stackTrace.toString(),
      fingerprint: fingerprint,
      sessionId: _sessionId,
      breadcrumbs: const <ArmBreadcrumb>[],
      context: await _buildContext(context),
      tags: sanitizeArmMap(tags) ?? const <String, dynamic>{},
      recoverySnapshot: sanitizeArmMap(recoverySnapshot),
      appVersion: _normalizedReleaseValue(appVersion),
      buildNumber: _normalizedReleaseValue(buildNumber),
      releaseChannel: _normalizedReleaseValue(releaseChannel),
      handled: handled,
    );
    final result = await _sink.record(request);
    return ArmCaptureResult(
      caseId: result.caseId,
      issueId: result.issueId,
      fingerprint: result.fingerprint,
      severity: result.severity,
      caseIdExposed: severity.index >= caseIdExposureThreshold.index,
    );
  }

  Future<T> runTracked<T>({
    required String feature,
    required String operation,
    required Future<T> Function() action,
    ArmSeverity severity = ArmSeverity.low,
    String category = 'server',
    Map<String, dynamic>? tags,
    Map<String, dynamic>? context,
    Map<String, dynamic>? recoverySnapshot,
    FutureOr<void> Function(ArmCaptureResult result)? onReported,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      final capture = await captureException(
        error: error,
        stackTrace: stackTrace,
        feature: feature,
        operation: operation,
        severity: severity,
        category: category,
        tags: tags,
        context: context,
        recoverySnapshot: recoverySnapshot,
        handled: true,
      );
      if (onReported != null) {
        await onReported(capture);
      }
      rethrow;
    }
  }

  static Future<T> runGuarded<T>({
    required ArmServer server,
    required Future<T> Function() body,
    String feature = 'server',
    String operation = 'zone_uncaught',
    ArmSeverity severity = ArmSeverity.serious,
    String category = 'runtime',
    Map<String, dynamic>? tags,
    Map<String, dynamic>? context,
    Map<String, dynamic>? recoverySnapshot,
  }) {
    final completer = Completer<T>();
    runZonedGuarded(
      () async {
        final value = await body();
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      (error, stackTrace) async {
        try {
          await server.captureException(
            error: error,
            stackTrace: stackTrace,
            feature: feature,
            operation: operation,
            severity: severity,
            category: category,
            tags: tags,
            context: context,
            recoverySnapshot: recoverySnapshot,
          );
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  Future<Map<String, dynamic>> _buildContext(
    Map<String, dynamic>? extraContext,
  ) async {
    final globalContext = contextBuilder == null
        ? null
        : sanitizeArmMap(await contextBuilder!());
    final safeExtraContext = sanitizeArmMap(extraContext);
    final sessionContext = <String, dynamic>{
      'id': _sessionId,
      'appId': appId,
      'environment': environment,
      'runtime': runtime,
      if (_normalizedReleaseValue(appVersion) case final value?)
        'appVersion': value,
      if (_normalizedReleaseValue(buildNumber) case final value?)
        'buildNumber': value,
      if (_normalizedReleaseValue(releaseChannel) case final value?)
        'releaseChannel': value,
    };
    return <String, dynamic>{
      if (globalContext != null && globalContext.isNotEmpty) ...globalContext,
      if (safeExtraContext != null && safeExtraContext.isNotEmpty)
        ...safeExtraContext,
      'appId': appId,
      'environment': environment,
      'runtime': runtime,
      'sessionId': _sessionId,
      if (_normalizedReleaseValue(appVersion) case final value?)
        'appVersion': value,
      if (_normalizedReleaseValue(buildNumber) case final value?)
        'buildNumber': value,
      if (_normalizedReleaseValue(releaseChannel) case final value?)
        'releaseChannel': value,
      'session': sessionContext,
    };
  }
}

String? _normalizedReleaseValue(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
