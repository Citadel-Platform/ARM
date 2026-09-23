import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:http/http.dart' as http;

/// Where a Flutter app sends ARM evidence: the shared ARM ingest, with the
/// client ID and the ARM ingest key (ARM → Set up ARM → *Issue the ingest
/// key*), like every other ARM sender.
///
/// Until 23/09/26 a Flutter app wrote Firestore itself, which meant it had to
/// be signed in to the client's Firebase project with write access to
/// `citadel-arm` — and had to be pointed at that database by hand, because the
/// SDKs default to `(default)`, where ARM never reads. Through the ingest the
/// app holds nothing but a public, send-only key, and the database is the
/// ingest's to choose.
class ArmIngestConnection {
  const ArmIngestConnection({
    required this.clientId,
    required this.ingestKey,
    required this.ingestUrl,
    this.timeout = const Duration(seconds: 10),
    this.httpClient,
  });

  final String clientId;
  final String ingestKey;
  final String ingestUrl;
  final Duration timeout;

  /// Tests only.
  final http.Client? httpClient;

  Uri endpoint(String path) {
    final String base = ingestUrl.endsWith('/')
        ? ingestUrl.substring(0, ingestUrl.length - 1)
        : ingestUrl;
    return Uri.parse('$base/v1/$path');
  }

  Map<String, String> get headers => <String, String>{
    'content-type': 'application/json; charset=utf-8',
    'x-citadel-client': clientId,
    'x-arm-key': ingestKey,
  };

  Future<Map<String, Object?>> post(String path, Object body) async {
    final http.Client client = httpClient ?? http.Client();
    try {
      final http.Response response = await client
          .post(endpoint(path), headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      final Object? decoded = response.body.isEmpty
          ? null
          : jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded is Map<String, Object?>
            ? decoded
            : const <String, Object?>{};
      }
      final Object? error = decoded is Map ? decoded['error'] : null;
      throw ArmIngestSendException(
        response.statusCode,
        error is Map && error['message'] is String
            ? error['message']! as String
            : 'The ARM ingest answered ${response.statusCode}.',
      );
    } finally {
      if (httpClient == null) client.close();
    }
  }
}

/// The ARM ingest refused a send, or could not be reached.
class ArmIngestSendException implements Exception {
  const ArmIngestSendException(this.status, this.message);

  /// The HTTP status, or 0 when nothing answered.
  final int status;
  final String message;

  @override
  String toString() => 'ArmIngestSendException($status): $message';
}

/// Sends each capture to the ARM ingest as it happens, and reports the case
/// and issue the ingest recorded — the ids an error dialog shows and a ticket
/// points at.
///
/// A screenshot on the request is not sent: nothing in ARM displays one yet,
/// and a megabyte per capture is a cost with no reader.
/// `operator/10-known-limits.md` says so.
class IngestArmSink implements ArmSink {
  IngestArmSink(this.connection, {Random? random})
    : _random = random ?? Random.secure();

  final ArmIngestConnection connection;
  final Random _random;

  @override
  Future<ArmCaptureResult> record(ArmCaptureRequest request) async {
    final String captureId = List<String>.generate(
      24,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    final Map<String, Object?> body = await connection.post(
      'captures',
      <Object?>[armIngestCaptureJson(request, captureId: captureId)],
    );
    final Object? captures = body['captures'];
    final Object? first = captures is List && captures.isNotEmpty
        ? captures.first
        : null;
    if (first is! Map ||
        first['caseId'] is! String ||
        first['issueId'] is! String) {
      throw const ArmIngestSendException(
        200,
        'The ARM ingest accepted the capture but did not name its case.',
      );
    }
    return ArmCaptureResult(
      caseId: first['caseId']! as String,
      issueId: first['issueId']! as String,
      fingerprint: request.fingerprint,
      severity: request.severity,
      caseIdExposed: request.severity.exposesCaseId,
    );
  }
}

/// One capture as the ARM ingest takes it (`POST /v1/captures`).
Map<String, Object?> armIngestCaptureJson(
  ArmCaptureRequest request, {
  required String captureId,
  DateTime? occurredAt,
}) => <String, Object?>{
  'captureId': captureId,
  'occurredAt': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
  'source': 'flutter',
  'severity': request.severity.wireName,
  'category': request.category,
  'feature': request.feature,
  'operation': request.operation,
  'message': request.message,
  'errorType': request.errorType,
  'errorName': ?request.errorName,
  'errorData': ?request.errorData,
  'stackTrace': request.stackTrace,
  'sessionId': request.sessionId,
  'handled': request.handled,
  'context': request.context,
  'tags': request.tags,
  'breadcrumbs': request.breadcrumbs.map((b) => b.toMap()).toList(),
  'recoverySnapshot': ?request.recoverySnapshot,
  'appVersion': ?request.appVersion,
  'buildNumber': ?request.buildNumber,
  'releaseChannel': ?request.releaseChannel,
  'environment': ?request.environment,
};

/// Opens a support ticket through the ARM ingest, into the Helpdesk.
///
/// Before 23/09/26 the SDK wrote `armTickets` into `citadel-arm`, which
/// nothing had read since the Helpdesk moved to Manifold on 08/09/26 — every
/// ticket sent from an app since then was written where nobody would see it.
class IngestArmTicketSink implements ArmTicketSink {
  IngestArmTicketSink(this.connection, {Random? random})
    : _random = random ?? Random.secure();

  final ArmIngestConnection connection;
  final Random _random;

  @override
  Future<String> open(ArmTicketRequest request) async {
    // One id per send, so a retry of this send opens one ticket.
    final String requestId = List<String>.generate(
      24,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    final Map<String, Object?> body = await connection
        .post('tickets', <String, Object?>{
          'requestId': requestId,
          'title': request.title,
          'description': request.description,
          'contact': ?request.contact,
          'caseId': ?request.caseId,
          'issueId': ?request.issueId,
          'sessionId': ?request.sessionId,
        });
    final Object? ticketId = body['ticketId'];
    if (ticketId is! String) {
      throw const ArmIngestSendException(
        200,
        'The ARM ingest accepted the ticket but did not name it.',
      );
    }
    return ticketId;
  }
}
