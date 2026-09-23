import 'dart:convert';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:crypto/crypto.dart';

import 'arm_private_service.dart';
import 'arm_project_router.dart';
import 'arm_service_models.dart' show ArmServiceErrorCode;

/// ARM's public ingest: evidence from a client's browser or server, into that
/// client's own `citadel-arm`.
///
/// Decided 23/09/26. One service in `citadel-platform`, shared by every client
/// — the shape Conduit's ingest already has — called with a **client ID** (the
/// Citadel project id) and an **ARM ingest key**. Nothing a client runs ever
/// writes Firestore itself: the rules on `armIssues` and `armCases` stay
/// `if false`, and this service writes under its own identity, granted on
/// `citadel-arm` and no other database.
///
/// **The fingerprint is computed here, not by the client.** Every client sends
/// what it saw — feature, operation, error type, message, stack — and this
/// service groups it with `tooling_core`, the reference. Clients can therefore
/// never disagree about what one fault is, however many languages they are
/// written in. The conformance set in `arm/contract` still holds each client's
/// own copy to the reference, for the client-side repeat suppression they do
/// before sending.
///
/// **Write-only.** The key ships in a web page and anyone can read it, so it
/// unlocks nothing that returns a client's evidence. Operator reads stay on the
/// private evidence service, behind the Platform API.

/// Where a capture came from. Recorded on the case; drives the stack
/// normalisation below.
enum ArmCaptureSource { web, node, php, dart, flutter, otlp }

/// A capture as a client sent it, validated.
final class ArmIngestCapture {
  const ArmIngestCapture({
    required this.captureId,
    required this.occurredAt,
    required this.source,
    required this.severity,
    required this.category,
    required this.feature,
    required this.operation,
    required this.message,
    required this.errorType,
    required this.stackTrace,
    required this.sessionId,
    required this.handled,
    required this.context,
    required this.tags,
    required this.breadcrumbs,
    this.errorName,
    this.errorData,
    this.appVersion,
    this.buildNumber,
    this.releaseChannel,
    this.environment,
  });

  /// The client's own id for this capture. A retry sends the same one, and
  /// the case id is derived from it, so a batch delivered twice records once.
  final String captureId;
  final DateTime occurredAt;
  final ArmCaptureSource source;
  final ArmSeverity severity;
  final String category;
  final String feature;
  final String operation;
  final String message;
  final String errorType;
  final String stackTrace;
  final String sessionId;
  final bool handled;
  final Map<String, dynamic> context;
  final Map<String, dynamic> tags;
  final List<ArmBreadcrumb> breadcrumbs;
  final String? errorName;
  final Map<String, dynamic>? errorData;
  final String? appVersion;
  final String? buildNumber;
  final String? releaseChannel;
  final String? environment;
}

/// Why a batch was refused, with the HTTP status the handler answers.
final class ArmIngestRejection implements Exception {
  const ArmIngestRejection(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => 'ArmIngestRejection($status $code): $message';
}

const int armIngestMaxBatch = 20;
const int armIngestMaxBodyBytes = 512 * 1024;
const int _maxStackLength = 16000;
const int _maxMessageLength = 4000;
const int _maxBreadcrumbs = 50;

/// Parses a batch body: a JSON array of captures.
List<ArmIngestCapture> parseArmIngestBatch(Object? decoded, {DateTime? now}) {
  if (decoded is! List) {
    throw const ArmIngestRejection(
      400,
      'invalidArgument',
      'The body must be a JSON array of captures.',
    );
  }
  if (decoded.isEmpty) {
    throw const ArmIngestRejection(400, 'invalidArgument', 'The batch is empty.');
  }
  if (decoded.length > armIngestMaxBatch) {
    throw const ArmIngestRejection(
      413,
      'payloadTooLarge',
      'At most $armIngestMaxBatch captures per batch.',
    );
  }
  final DateTime received = (now ?? DateTime.now()).toUtc();
  return <ArmIngestCapture>[
    for (var i = 0; i < decoded.length; i += 1)
      _parseCapture(decoded[i], 'captures[$i]', received),
  ];
}

ArmIngestCapture _parseCapture(Object? raw, String at, DateTime received) {
  if (raw is! Map) {
    throw ArmIngestRejection(400, 'invalidArgument', '$at must be an object.');
  }
  final map = Map<String, Object?>.from(raw);

  String required(String key, {int max = 200}) {
    final Object? value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw ArmIngestRejection(400, 'invalidArgument', '$at.$key is required.');
    }
    final String text = value.trim();
    return text.length <= max ? text : text.substring(0, max);
  }

  String? optional(String key, {int max = 200}) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is! String) {
      throw ArmIngestRejection(400, 'invalidArgument', '$at.$key must be a string.');
    }
    final String text = value.trim();
    if (text.isEmpty) return null;
    return text.length <= max ? text : text.substring(0, max);
  }

  Map<String, dynamic>? object(String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is! Map) {
      throw ArmIngestRejection(400, 'invalidArgument', '$at.$key must be an object.');
    }
    return sanitizeArmMap(Map<String, dynamic>.from(value));
  }

  final String captureId = required('captureId', max: 64);
  if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(captureId)) {
    throw ArmIngestRejection(
      400,
      'invalidArgument',
      '$at.captureId must be 1–64 letters, digits, "-" or "_".',
    );
  }

  final DateTime? parsedAt = DateTime.tryParse(required('occurredAt', max: 40));
  if (parsedAt == null) {
    throw ArmIngestRejection(400, 'invalidArgument', '$at.occurredAt must be ISO 8601.');
  }
  // A client clock can be anything. Kept when plausible, otherwise the time it
  // arrived: a case dated next year sorts above every real incident.
  final DateTime occurredAt = parsedAt.toUtc().isAfter(
        received.add(const Duration(minutes: 5)),
      ) ||
      parsedAt.toUtc().isBefore(received.subtract(const Duration(days: 7)))
      ? received
      : parsedAt.toUtc();

  final String sourceName = optional('source', max: 20) ?? 'web';
  final ArmCaptureSource source = ArmCaptureSource.values.firstWhere(
    (ArmCaptureSource s) => s.name == sourceName,
    orElse: () => throw ArmIngestRejection(
      400,
      'invalidArgument',
      '$at.source must be one of ${ArmCaptureSource.values.map((s) => s.name).join(', ')}.',
    ),
  );

  final String severityName = optional('severity', max: 20) ?? 'low';
  final ArmSeverity severity = ArmSeverity.values.firstWhere(
    (ArmSeverity s) => s.wireName == severityName,
    orElse: () => throw ArmIngestRejection(
      400,
      'invalidArgument',
      '$at.severity must be one of ${ArmSeverity.values.map((s) => s.wireName).join(', ')}.',
    ),
  );

  final Object? handled = map['handled'];
  if (handled != null && handled is! bool) {
    throw ArmIngestRejection(400, 'invalidArgument', '$at.handled must be a boolean.');
  }

  final Object? rawCrumbs = map['breadcrumbs'];
  if (rawCrumbs != null && rawCrumbs is! List) {
    throw ArmIngestRejection(400, 'invalidArgument', '$at.breadcrumbs must be an array.');
  }
  final List<ArmBreadcrumb> breadcrumbs = <ArmBreadcrumb>[
    for (final Object? crumb in (rawCrumbs as List? ?? const <Object?>[])
        .reversed
        .take(_maxBreadcrumbs)
        .toList()
        .reversed)
      if (_breadcrumb(crumb) case final ArmBreadcrumb parsed) parsed,
  ];

  final Object? rawStack = map['stackTrace'];
  final String stackTrace = rawStack is String
      ? (rawStack.length <= _maxStackLength
            ? rawStack
            : rawStack.substring(0, _maxStackLength))
      : '';
  final Object? rawMessage = map['message'];
  final String message = rawMessage is String
      ? (rawMessage.length <= _maxMessageLength
            ? rawMessage
            : rawMessage.substring(0, _maxMessageLength))
      : '';

  return ArmIngestCapture(
    captureId: captureId,
    occurredAt: occurredAt,
    source: source,
    severity: severity,
    category: optional('category', max: 60) ?? 'exception',
    feature: required('feature', max: 120),
    operation: required('operation', max: 120),
    message: message,
    errorType: required('errorType', max: 200),
    stackTrace: stackTrace,
    sessionId: required('sessionId', max: 128),
    handled: handled as bool? ?? false,
    context: object('context') ?? <String, dynamic>{},
    tags: object('tags') ?? <String, dynamic>{},
    breadcrumbs: breadcrumbs,
    errorName: optional('errorName', max: 200),
    errorData: object('errorData'),
    appVersion: optional('appVersion', max: 60),
    buildNumber: optional('buildNumber', max: 60),
    releaseChannel: optional('releaseChannel', max: 60),
    environment: optional('environment', max: 60),
  );
}

/// A breadcrumb that does not parse is dropped, not refused: the capture it
/// travels with is the evidence, and one malformed crumb is not a reason to
/// lose it.
ArmBreadcrumb? _breadcrumb(Object? raw) {
  if (raw is! Map) return null;
  final Object? message = raw['message'];
  final DateTime? at = raw['timestamp'] is String
      ? DateTime.tryParse(raw['timestamp'] as String)
      : null;
  if (message is! String || message.isEmpty || at == null) return null;
  final Object? level = raw['level'];
  final Object? category = raw['category'];
  final Object? data = raw['data'];
  return ArmBreadcrumb(
    message: message.length <= 500 ? message : message.substring(0, 500),
    level: level is String && level.isNotEmpty ? level : 'info',
    timestamp: at.toUtc(),
    category: category is String && category.isNotEmpty ? category : null,
    data: data is Map ? sanitizeArmMap(Map<String, dynamic>.from(data)) : null,
  );
}

/// The stack as the fingerprint sees it.
///
/// `tooling_core`'s normaliser was written for Dart stacks. A browser stack
/// defeats it in two ways that would split one fault into many issues, so a
/// web capture is prepared first — for grouping only; the case keeps the stack
/// exactly as sent:
///
/// - V8 opens a stack with `TypeError: <message>`. The message is normalised
///   (numbers become `<n>`) but this copy of it is not, so "order 9817" and
///   "order 1042" would be two issues. The line is dropped.
/// - A frame's URL can carry the page's query string; it is dropped.
/// - Bundlers put a content hash in chunk names (`page-3f9a1c.js`,
///   `main.8e2a1b4c.js`), which changes on every deploy. The hash is dropped,
///   so a fault survives a release as the same issue — which is what release
///   health needs to say whether a release fixed it.
String armFingerprintStack(ArmIngestCapture capture) {
  if (capture.source == ArmCaptureSource.php) {
    // PHP names a frame `src/Booking.php(118): App\Booking->confirm()`. The
    // reference strips a Dart or V8 `:line:column` but not PHP's `(line)`,
    // so any edit above the fault would make it a new issue — and every
    // deploy is an edit. The line goes, for grouping only.
    return capture.stackTrace.replaceAllMapped(
      RegExp(r'(\.(?:php|phtml|inc))\(\d+\)'),
      (Match m) => m[1]!,
    );
  }
  if (capture.source != ArmCaptureSource.web &&
      capture.source != ArmCaptureSource.node) {
    return capture.stackTrace;
  }
  final List<String> lines = capture.stackTrace.split('\n');
  if (lines.isNotEmpty) {
    final String first = lines.first.trim();
    if (first == capture.errorType ||
        first.startsWith('${capture.errorType}:') ||
        (capture.errorName != null && first.startsWith('${capture.errorName}:'))) {
      lines.removeAt(0);
    }
  }
  return lines
      .map(
        (String line) => line
            // A frame's URL with its query: the page an inline script ran
            // on, carrying whatever that visitor's address carried. `arm-web`
            // strips it before sending; this keeps an older or hand-written
            // sender from splitting one fault by query string.
            .replaceAllMapped(
              RegExp(r'(\b(?:https?|file)://[^\s?#()]+)[?#][^\s()]*?(:\d+:\d+|:\d+)?(?=[\s)]|$)'),
              (Match m) => '${m[1]}${m[2] ?? ''}',
            )
            .replaceAllMapped(
              RegExp(r'([-.])[0-9a-f]{6,}(\.m?js)', caseSensitive: false),
              (Match m) => m[2]!,
            ),
      )
      .join('\n');
}

/// `ARM-yyyymmdd-XXXXXXXX`, the format `tooling_core` issues, derived from the
/// client and its capture id so a redelivered capture lands on the same case.
String armIngestCaseId(String clientId, ArmIngestCapture capture) {
  final DateTime day = capture.occurredAt.toUtc();
  final String date =
      '${day.year.toString().padLeft(4, '0')}'
      '${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';
  final String suffix = sha1
      .convert(utf8.encode('$clientId\n${capture.captureId}'))
      .toString()
      .substring(0, 8)
      .toUpperCase();
  return 'ARM-$date-$suffix';
}

/// A capture turned into what `tooling_core` builds documents from.
ArmCaptureRequest armCaptureRequestFor(ArmIngestCapture capture) {
  final String fingerprint = buildArmFingerprint(
    feature: capture.feature,
    operation: capture.operation,
    errorType: capture.errorType,
    message: capture.message,
    stackTrace: StackTrace.fromString(armFingerprintStack(capture)),
  );
  return ArmCaptureRequest(
    severity: capture.severity,
    category: capture.category,
    feature: capture.feature,
    operation: capture.operation,
    message: capture.message,
    errorType: capture.errorType,
    stackTrace: capture.stackTrace,
    fingerprint: fingerprint,
    sessionId: capture.sessionId,
    breadcrumbs: capture.breadcrumbs,
    context: capture.context,
    tags: capture.tags,
    errorName: capture.errorName,
    errorData: capture.errorData,
    appVersion: capture.appVersion,
    buildNumber: capture.buildNumber,
    releaseChannel: capture.releaseChannel,
    environment: capture.environment,
    handled: capture.handled,
  );
}

/// The ingest key a client presents, checked against the registry.
abstract interface class ArmIngestKeyRegistry {
  /// True when [key] is the current ARM ingest key of [clientId].
  Future<bool> verify(String clientId, String key);
}

/// What one capture came to.
final class ArmIngestOutcome {
  const ArmIngestOutcome({
    required this.captureId,
    required this.caseId,
    required this.issueId,
    required this.duplicate,
  });

  final String captureId;
  final String caseId;
  final String issueId;

  /// The case already existed: a redelivery, recorded once.
  final bool duplicate;

  Map<String, Object?> toJson() => <String, Object?>{
    'captureId': captureId,
    'caseId': caseId,
    'issueId': issueId,
    'duplicate': duplicate,
  };
}

/// Writes one capture's case and issue into a client's `citadel-arm`.
abstract interface class ArmIngestStore {
  Future<ArmIngestOutcome> record({
    required ArmProjectTarget target,
    required String caseId,
    required ArmIngestCapture capture,
    required ArmCaptureRequest request,
    required DateTime receivedAt,
  });
}

/// A fixed one-minute window per client, per instance.
///
/// Per instance rather than global because the service scales to zero and has
/// no shared store to count in; the ceiling is therefore this times the
/// instance cap, which is the same arrangement Conduit's ingest makes.
final class ArmIngestRateLimiter {
  ArmIngestRateLimiter({required this.capturesPerMinute, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int capturesPerMinute;
  final DateTime Function() _clock;
  final Map<String, ({int minute, int count})> _windows =
      <String, ({int minute, int count})>{};

  bool admit(String clientId, int cost) {
    final int minute = _clock().millisecondsSinceEpoch ~/ 60000;
    final current = _windows[clientId];
    final int count = current == null || current.minute != minute ? 0 : current.count;
    if (count + cost > capturesPerMinute) return false;
    _windows[clientId] = (minute: minute, count: count + cost);
    if (_windows.length > 10000) {
      _windows.removeWhere((_, w) => w.minute != minute);
    }
    return true;
  }
}

/// The ingest, independent of HTTP.
final class ArmIngestService {
  ArmIngestService({
    required ArmIngestKeyRegistry keys,
    required ArmProjectRouter router,
    required ArmIngestStore store,
    required ArmIngestRateLimiter rateLimiter,
    DateTime Function()? clock,
  }) : _keys = keys,
       _router = router,
       _store = store,
       _rateLimiter = rateLimiter,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final ArmIngestKeyRegistry _keys;
  final ArmProjectRouter _router;
  final ArmIngestStore _store;
  final ArmIngestRateLimiter _rateLimiter;
  final DateTime Function() _clock;

  Future<List<ArmIngestOutcome>> accept({
    required String? clientId,
    required String? key,
    required Object? body,
  }) async {
    final String client = clientId?.trim() ?? '';
    final String presented = key?.trim() ?? '';
    // One answer for an unknown client and a wrong key, so the endpoint cannot
    // be used to learn which client ids exist.
    const ArmIngestRejection unauthenticated = ArmIngestRejection(
      401,
      'unauthenticated',
      'The client ID and ARM ingest key do not match a client.',
    );
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,62}$').hasMatch(client) || presented.isEmpty) {
      throw unauthenticated;
    }
    final DateTime now = _clock();
    final List<ArmIngestCapture> captures = parseArmIngestBatch(body, now: now);
    if (!await _keys.verify(client, presented)) {
      throw unauthenticated;
    }
    if (!_rateLimiter.admit(client, captures.length)) {
      throw const ArmIngestRejection(
        429,
        'resourceExhausted',
        'Too many captures for this client this minute. Retry later.',
      );
    }

    final ArmProjectTarget target;
    try {
      target = await _router.resolve(client, offering: ArmRoutedOffering.evidence);
    } on ArmServiceException catch (error) {
      throw _rejectionFor(error);
    }

    final List<ArmIngestOutcome> outcomes = <ArmIngestOutcome>[];
    for (final ArmIngestCapture capture in captures) {
      try {
        outcomes.add(
          await _store.record(
            target: target,
            caseId: armIngestCaseId(client, capture),
            capture: capture,
            request: armCaptureRequestFor(capture),
            receivedAt: now,
          ),
        );
      } on ArmServiceException catch (error) {
        throw _rejectionFor(error);
      }
    }
    return outcomes;
  }

  ArmIngestRejection _rejectionFor(ArmServiceException error) =>
      switch (error.code) {
        // ARM off, the project archived, or its data plane unbuilt or ungranted.
        // The client's code is fine; the operator has a step to finish. 409, as
        // every other product answers a switched-off offering.
        ArmServiceErrorCode.failedPrecondition ||
        ArmServiceErrorCode.notFound => ArmIngestRejection(
          409,
          'failedPrecondition',
          error.message,
        ),
        _ => ArmIngestRejection(503, 'unavailable', error.message),
      };
}
