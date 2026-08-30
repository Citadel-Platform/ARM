import 'dart:async';
import 'dart:collection';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:flutter/foundation.dart';

class ArmClient {
  ArmClient({
    required ArmSink sink,
    required this.appId,
    required this.environment,
    this.appVersion,
    this.buildNumber,
    this.releaseChannel,
    this.contextBuilder,
    this.userIdProvider,
    this.userEmailProvider,
    this.routeProvider,
    this.maxBreadcrumbs = 40,
    this.capturePrints = true,
    this.caseIdExposureThreshold = ArmSeverity.moderate,
    ArmTicketSink? ticketSink,
    this.duplicateReportInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _sink = sink,
       _ticketSink = ticketSink,
       _clock = clock ?? _utcNow,
       _sessionId = buildArmSessionId(appId);

  static DateTime _utcNow() => DateTime.now().toUtc();

  final ArmSink _sink;

  /// Where a support ticket goes, when the application offers one. Absent on
  /// an application that has not configured tickets, and the ticket API then
  /// refuses rather than showing somebody a form that discards what they
  /// wrote.
  final ArmTicketSink? _ticketSink;
  final DateTime Function() _clock;
  final String appId;
  final String environment;
  final String? appVersion;
  final String? buildNumber;
  final String? releaseChannel;
  final ArmContextBuilder? contextBuilder;
  final ArmValueProvider? userIdProvider;
  final ArmValueProvider? userEmailProvider;
  final ArmValueProvider? routeProvider;
  final int maxBreadcrumbs;
  final bool capturePrints;
  final ArmSeverity caseIdExposureThreshold;

  /// How often one fingerprint may be reported again within a session.
  ///
  /// The same fault in a rebuild loop produces the same case a thousand times,
  /// which costs the client a thousand writes and tells a reader nothing the
  /// first one did not. Repeats inside this window are counted rather than
  /// sent, and the next report carries the count — because a loop that erred a
  /// thousand times and one that erred once must not read the same.
  final Duration duplicateReportInterval;

  final ListQueue<ArmBreadcrumb> _breadcrumbs = ListQueue<ArmBreadcrumb>();
  final Map<String, _ArmFingerprintSession> _seen =
      <String, _ArmFingerprintSession>{};
  final String _sessionId;

  String get sessionId => _sessionId;

  /// How many captures of [fingerprint] have been suppressed since the last
  /// one that was actually sent. Zero for a fingerprint never seen.
  int suppressedCountFor(String fingerprint) =>
      _seen[fingerprint]?.suppressed ?? 0;

  /// Opens a support ticket, pegged to a case log when there is one.
  ///
  /// Called from an error dialog's own button: the person who hit the fault
  /// gives a way to reach them back, and the ticket names the case log and
  /// fingerprint so the developer reading it is looking at the same failure.
  /// Refuses loudly on an application with no ticket sink — a form that
  /// silently discarded somebody's words would be worse than no button.
  Future<String> openSupportTicket({
    required String title,
    required String description,
    String? contact,
    ArmCaptureResult? capture,
  }) async {
    final ArmTicketSink? sink = _ticketSink;
    if (sink == null) {
      throw StateError(
        'This application has no ARM ticket sink configured, so a ticket '
        'cannot be opened.',
      );
    }
    final String ticketId = await sink.open(
      ArmTicketRequest(
        title: title,
        description: description,
        contact: contact,
        caseId: capture?.caseId,
        issueId: capture?.issueId,
        sessionId: _sessionId,
      ),
    );
    addBreadcrumb(
      'ARM ticket $ticketId opened',
      level: 'info',
      category: 'arm',
      data: <String, dynamic>{
        if (capture != null) 'caseId': capture.caseId,
        if (capture != null) 'issueId': capture.issueId,
      },
    );
    return ticketId;
  }

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
    // Repeats of one fingerprint inside one session are counted, not sent.
    // The count travels with the next report that is sent, so nothing about
    // how often this happened is lost.
    final DateTime now = _clock();
    final _ArmFingerprintSession session = _seen.putIfAbsent(
      fingerprint,
      _ArmFingerprintSession.new,
    );
    if (session.lastReportedAt case final DateTime last
        when now.difference(last) < duplicateReportInterval) {
      session.suppressed += 1;
      addBreadcrumb(
        'ARM case suppressed as a repeat of $fingerprint',
        level: 'info',
        category: 'arm',
        data: <String, dynamic>{'suppressed': session.suppressed},
      );
      final ArmCaptureResult? previous = session.lastResult;
      if (previous != null) {
        return previous;
      }
    }
    final int suppressedSinceLastReport = session.suppressed;
    session.suppressed = 0;
    session.lastReportedAt = now;

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
      tags: <String, dynamic>{
        ...?sanitizeArmMap(tags),
        // Only when there were any. A `0` on every case would be noise on the
        // overwhelming majority of them.
        if (suppressedSinceLastReport > 0)
          'suppressedSinceLastReport': suppressedSinceLastReport,
      },
      recoverySnapshot: recoverySnapshot,
      screenshot: screenshot,
      appVersion: _normalizedReleaseValue(appVersion),
      buildNumber: _normalizedReleaseValue(buildNumber),
      releaseChannel: _normalizedReleaseValue(releaseChannel),
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
    final ArmCaptureResult captured = ArmCaptureResult(
      caseId: result.caseId,
      issueId: result.issueId,
      fingerprint: result.fingerprint,
      severity: result.severity,
      caseIdExposed: severity.index >= caseIdExposureThreshold.index,
    );
    // Kept so a suppressed repeat can answer with the case that was actually
    // recorded: an error dialog showing "no case id" on the second occurrence
    // of the same fault would look like the SDK had stopped working.
    session.lastResult = captured;
    return captured;
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
      if (_normalizedReleaseValue(appVersion) case final value?)
        'appVersion': value,
      if (_normalizedReleaseValue(buildNumber) case final value?)
        'buildNumber': value,
      if (_normalizedReleaseValue(releaseChannel) case final value?)
        'releaseChannel': value,
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
      if (_normalizedReleaseValue(appVersion) case final value?)
        'appVersion': value,
      if (_normalizedReleaseValue(buildNumber) case final value?)
        'buildNumber': value,
      if (_normalizedReleaseValue(releaseChannel) case final value?)
        'releaseChannel': value,
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

String? _normalizedReleaseValue(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}


/// What has already been reported for one fingerprint in this session.
class _ArmFingerprintSession {
  DateTime? lastReportedAt;
  ArmCaptureResult? lastResult;
  int suppressed = 0;
}
