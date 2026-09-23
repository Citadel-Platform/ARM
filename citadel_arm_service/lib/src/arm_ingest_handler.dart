import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'arm_ingest.dart';

/// The browser scripts the ingest serves at `/sdk/v1/`: `citadel-core.js` and
/// `arm.js`, bundled into the image by `cloudbuild.arm.yaml`.
///
/// From the ingest's own origin so a client's Content-Security-Policy names
/// one Citadel host for ARM — the one captures already go to. Loaded into
/// memory once at start; an image built without the bundle step has none and
/// answers 404 saying so.
final class ArmSdkAssets {
  ArmSdkAssets._(this._files);

  static const List<String> names = <String>['citadel-core.js', 'arm.js'];

  final Map<String, ({List<int> bytes, String etag})> _files;

  static ArmSdkAssets load(Directory directory) => ArmSdkAssets._(
    <String, ({List<int> bytes, String etag})>{
      for (final String name in names)
        if (File('${directory.path}/$name').existsSync())
          name: _asset(File('${directory.path}/$name').readAsBytesSync()),
    },
  );

  factory ArmSdkAssets.fromMap(Map<String, String> sources) => ArmSdkAssets._(
    <String, ({List<int> bytes, String etag})>{
      for (final MapEntry<String, String> e in sources.entries)
        e.key: _asset(utf8.encode(e.value)),
    },
  );

  static ({List<int> bytes, String etag}) _asset(List<int> bytes) =>
      (bytes: bytes, etag: '"${sha256.convert(bytes).toString().substring(0, 16)}"');

  bool get isEmpty => _files.isEmpty;
  Iterable<String> get loaded => _files.keys;
  ({List<int> bytes, String etag})? operator [](String name) => _files[name];
}

/// The public HTTP face of the ARM ingest.
///
///   POST /v1/captures      a JSON array of captures
///   GET  /healthz, /v1/healthz
///
/// The client ID and key travel in `X-Citadel-Client` and `X-ARM-Key`, or —
/// for a browser's last batch, sent by `navigator.sendBeacon`, which can set
/// no header — as the `client` and `key` query parameters. For the same reason
/// the body is read whatever its content type: a beacon sends `text/plain` so
/// the browser does not need a preflight it could not wait for.
///
/// CORS answers every origin. The service sets and reads no cookie, and the
/// key is public by construction — it ships in the page — so an origin
/// allowlist would protect nothing and would have to be configured per client
/// site before one error could arrive. The Conduit ingest reasons the same
/// way (`G4-56`).
Handler createArmIngestHandler({
  required ArmIngestService service,
  ArmSdkAssets? sdkAssets,
}) {
  return (Request request) async {
    final Response response = await _route(request, service, sdkAssets);
    return response.change(headers: _corsHeaders);
  };
}

Future<Response> _route(
  Request request,
  ArmIngestService service,
  ArmSdkAssets? sdkAssets,
) async {
  final String requestId =
      request.headers['x-request-id'] ??
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  if (request.method == 'OPTIONS') return Response(204);

  final List<String> path = request.url.pathSegments;
  if (request.method == 'GET' &&
      ((path.length == 1 && path[0] == 'healthz') ||
          (path.length == 2 && path[0] == 'v1' && path[1] == 'healthz'))) {
    return _json(200, <String, Object?>{'status': 'ok', 'requestId': requestId});
  }

  if ((request.method == 'GET' || request.method == 'HEAD') &&
      path.length == 3 &&
      path[0] == 'sdk' &&
      path[1] == 'v1') {
    final asset = sdkAssets?[path[2]];
    if (asset == null) {
      return _error(
        404,
        'notFound',
        ArmSdkAssets.names.contains(path[2])
            ? 'This ARM build does not carry the web SDK. It is bundled by '
                  'cloudbuild.arm.yaml; an image built another way has none.'
            : 'No web SDK script is named ${path[2]}.',
        requestId,
      );
    }
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/javascript; charset=utf-8',
      // An hour, then revalidated: every page view of every client site asks,
      // and a fix should not take days to reach them.
      'cache-control': 'public, max-age=3600',
      'etag': asset.etag,
      'x-content-type-options': 'nosniff',
      'cross-origin-resource-policy': 'cross-origin',
    };
    if (request.headers['if-none-match'] == asset.etag) {
      return Response(304, headers: headers);
    }
    return Response.ok(
      request.method == 'HEAD' ? null : asset.bytes,
      headers: headers,
    );
  }

  if (!(request.method == 'POST' &&
      path.length == 2 &&
      path[0] == 'v1' &&
      path[1] == 'captures')) {
    return _error(404, 'notFound', 'No ARM ingest route matches.', requestId);
  }

  try {
    final int? declared = request.contentLength;
    if (declared != null && declared > armIngestMaxBodyBytes) {
      throw const ArmIngestRejection(
        413,
        'payloadTooLarge',
        'The batch is larger than $armIngestMaxBodyBytes bytes.',
      );
    }
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > armIngestMaxBodyBytes) {
        throw const ArmIngestRejection(
          413,
          'payloadTooLarge',
          'The batch is larger than $armIngestMaxBodyBytes bytes.',
        );
      }
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const ArmIngestRejection(400, 'invalidArgument', 'The body is not JSON.');
    }
    final String? clientId =
        request.headers['x-citadel-client'] ?? request.url.queryParameters['client'];
    final String? key =
        request.headers['x-arm-key'] ?? request.url.queryParameters['key'];

    final List<ArmIngestOutcome> outcomes = await service.accept(
      clientId: clientId,
      key: key,
      body: body,
    );
    return _json(202, <String, Object?>{
      'requestId': requestId,
      'accepted': outcomes.where((o) => !o.duplicate).length,
      'duplicates': outcomes.where((o) => o.duplicate).length,
      'captures': outcomes.map((o) => o.toJson()).toList(),
    });
  } on ArmIngestRejection catch (rejection) {
    return _error(rejection.status, rejection.code, rejection.message, requestId);
  } on Object catch (error, stack) {
    // Opaque to the caller, whole for the operator, tied by the request id.
    stderr.writeln('ARM ingest $requestId failed: $error\n$stack');
    return _error(500, 'internal', 'The ARM ingest failed.', requestId);
  }
}

Response _json(int status, Map<String, Object?> body) => Response(
  status,
  body: jsonEncode(body),
  headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
);

Response _error(int status, String code, String message, String requestId) =>
    _json(status, <String, Object?>{
      'error': <String, Object?>{
        'code': code,
        'message': message,
        'requestId': requestId,
        'retryable': status == 429 || status >= 500,
      },
    });

const Map<String, String> _corsHeaders = <String, String>{
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers':
      'content-type, x-citadel-client, x-arm-key, x-request-id',
  'access-control-max-age': '3600',
};
