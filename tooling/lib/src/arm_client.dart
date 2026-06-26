import 'dart:async';
import 'dart:collection';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:flutter/foundation.dart';

class ArmClient {
  ArmClient({
    required ArmSink sink,
    required this.appId,
    required this.environment,
    this.contextBuilder,
    this.userIdProvider,
    this.userEmailProvider,
    this.routeProvider,
    this.maxBreadcrumbs = 40,
    this.capturePrints = true,
    this.caseIdExposureThreshold = ArmSeverity.moderate,
  }) : _sink = sink,
       _sessionId = buildArmSessionId(appId);

  final ArmSink _sink;
  final String appId;
  final String environment;
  final ArmContextBuilder? contextBuilder;
  final ArmValueProvider? userIdProvider;
  final ArmValueProvider? userEmailProvider;
  final ArmValueProvider? routeProvider;
  final int maxBreadcrumbs;
  final bool capturePrints;
  final ArmSeverity caseIdExposureThreshold;

  final ListQueue<ArmBreadcrumb> _breadcrumbs = ListQueue<ArmBreadcrumb>();
  final String _sessionId;

  String get sessionId => _sessionId;

  void addBreadcrumb(
    String message, {
    String level = 'info',
    String? category,
    Map<String, dynamic>? data,
  }) {
    _breadcrumbs.add(
      ArmBreadcrumb(
        message: message,
        level: level,
        category: category,
        data: sanitizeArmMap(data),
        timestamp: DateTime.now().toUtc(),
      ),
    );
    while (_breadcrumbs.length > maxBreadcrumbs) {
      _breadcrumbs.removeFirst();
    }
  }

  ZoneSpecification? createZoneSpecification() {
    if (!capturePrints) return null;
    return ZoneSpecification(
      print: (self, parent, zone, line) {
        addBreadcrumb(
          line,
          level: kDebugMode ? 'debug' : 'info',
          category: 'print',
        );
        parent.print(zone, line);
      },
    );
  }

  Future<ArmCaptureResult> captureException({
    required Object error,
    required StackTrace stackTrace,
    required String feature,
    required String operation,
    ArmSeverity severity = ArmSeverity.low,
    String category = 'exception',
    Map<String, dynamic>? tags,
    ArmSnapshotBuilder? recoverySnapshotBuilder,
    ArmScreenshotCapture? screenshotCapture,
    bool handled = false,
  }) async {
    final message = error.toString();
    final fingerprint = buildArmFingerprint(
      feature: feature,
      operation: operation,
      errorType: error.runtimeType.toString(),
      message: message,
      stackTrace: stackTrace,
    );
    final context = await _buildContext();
    final recoverySnapshot = recoverySnapshotBuilder == null
        ? null
        : sanitizeArmMap(await recoverySnapshotBuilder());
    final screenshot = screenshotCapture == null
        ? null
        : await screenshotCapture();
    final request = ArmCaptureRequest(
      severity: severity,
      category: category,
      feature: feature,
      operation: operation,
      message: message,
      errorType: error.runtimeType.toString(),
      stackTrace: stackTrace.toString(),
      fingerprint: fingerprint,
      sessionId: _sessionId,
      breadcrumbs: _breadcrumbs.toList(growable: false),
      context: context,
      tags: sanitizeArmMap(tags) ?? const <String, dynamic>{},
      recoverySnapshot: recoverySnapshot,
      screenshot: screenshot,
      handled: handled,
    );
    final result = await _sink.record(request);
    addBreadcrumb(
      'ARM case ${result.caseId} recorded',
      level: 'warn',
      category: 'arm',
      data: <String, dynamic>{
        'issueId': result.issueId,
        'feature': feature,
        'operation': operation,
      },
    );
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
    String category = 'exception',
    Map<String, dynamic>? tags,
    ArmSnapshotBuilder? recoverySnapshotBuilder,
    ArmScreenshotCapture? screenshotCapture,
    FutureOr<void> Function(ArmCaptureResult result)? onReported,
  }) async {
    try {
      addBreadcrumb(
        '$feature.$operation started',
        level: 'info',
        category: 'operation',
      );
      final result = await action();
      addBreadcrumb(
        '$feature.$operation completed',
        level: 'info',
        category: 'operation',
      );
      return result;
    } catch (error, stackTrace) {
      try {
        final capture = await captureException(
          error: error,
          stackTrace: stackTrace,
          feature: feature,
          operation: operation,
          severity: severity,
          category: category,
          tags: tags,
          recoverySnapshotBuilder: recoverySnapshotBuilder,
          screenshotCapture: screenshotCapture,
          handled: true,
        );
        if (onReported != null) {
          await onReported(capture);
        }
      } catch (captureError) {
        addBreadcrumb(
          'ARM capture failed: $captureError',
          level: 'error',
          category: 'arm',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _buildContext() async {
    final extra = contextBuilder == null ? null : await contextBuilder!();
    final String? userId = _resolvedProviderValue(userIdProvider);
    final String? userEmail = _resolvedProviderValue(userEmailProvider);
    final String? route = _resolvedProviderValue(routeProvider);
    final Map<String, dynamic>? safeExtra = sanitizeArmMap(extra);
    final Map<String, dynamic> sessionContext = <String, dynamic>{
      'id': _sessionId,
      'appId': appId,
      'environment': environment,
      'releaseMode': kReleaseMode,
      if (userId != null) 'userId': userId,
      if (userEmail != null) 'userEmail': userEmail,
      if (route != null) 'route': route,
    };
    return <String, dynamic>{
      if (safeExtra != null && safeExtra.isNotEmpty) ...safeExtra,
      'appId': appId,
      'environment': environment,
      'sessionId': _sessionId,
      'releaseMode': kReleaseMode,
      if (userId != null) 'userId': userId,
      if (userEmail != null) 'userEmail': userEmail,
      if (route != null) 'route': route,
      'session': sessionContext,
    };
  }

  static String? _resolvedProviderValue(ArmValueProvider? provider) {
    final String? rawValue = provider?.call();
    if (rawValue == null) {
      return null;
    }
    final String value = rawValue.trim();
    return value.isEmpty ? null : value;
  }
}
