import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'arm_ingest.dart';

/// OpenTelemetry into ARM (Feature 1.6.4).
///
/// The escape hatch for every runtime Citadel ships no package for — Python,
/// Go, Java, .NET, a Laravel app with an exporter already configured. The
/// ingest accepts OTLP/HTTP at the paths an exporter appends to its endpoint,
/// `/v1/traces` and `/v1/logs`, in either encoding an exporter may use:
/// protobuf (the default for most SDKs) and JSON.
///
///     OTEL_EXPORTER_OTLP_ENDPOINT=https://<arm-ingest>
///     OTEL_EXPORTER_OTLP_HEADERS=x-citadel-client=<client id>,x-arm-key=<key>
///
/// **ARM is not a tracing backend.** Only what went wrong becomes evidence:
///
/// - an `exception` event on a span (the semantic convention every SDK's
///   `recordException` writes), one capture per event;
/// - a span whose status is ERROR with no exception event, as one capture;
/// - a log record at ERROR or above.
///
/// Everything else in the export is acknowledged and dropped. Each capture
/// becomes an ordinary ARM capture with `source: otlp`, grouped by the same
/// rule as every other sender.
///
/// A capture's id is derived from the trace, span and event, so an exporter
/// retrying a batch it already delivered records nothing twice.

enum ArmOtlpSignal { traces, logs }

/// The most one export may decompress to. An exporter's batch is far
/// smaller; this bounds what a gzip bomb can cost.
const int armOtlpMaxDecodedBytes = 16 * 1024 * 1024;

/// Converts one OTLP export into ARM capture maps, in the JSON shape
/// `parseArmIngestBatch` takes. Throws [ArmIngestRejection] (400) when the
/// body is not an export of [signal].
List<Map<String, Object?>> armCapturesFromOtlp({
  required ArmOtlpSignal signal,
  required List<int> body,
  required bool protobuf,
}) {
  final Map<String, Object?> export;
  try {
    export = protobuf
        ? (signal == ArmOtlpSignal.traces
              ? _decodeTraceExport(Uint8List.fromList(body))
              : _decodeLogsExport(Uint8List.fromList(body)))
        : _jsonObject(jsonDecode(utf8.decode(body)));
  } on ArmIngestRejection {
    rethrow;
  } on Object {
    throw ArmIngestRejection(
      400,
      'invalidArgument',
      'The body is not an OTLP ${signal.name} export in '
          '${protobuf ? 'protobuf' : 'JSON'}.',
    );
  }
  return signal == ArmOtlpSignal.traces
      ? _fromTraces(export)
      : _fromLogs(export);
}

// ------------------------------------------------------------------ mapping

List<Map<String, Object?>> _fromTraces(Map<String, Object?> export) {
  final List<Map<String, Object?>> captures = <Map<String, Object?>>[];
  for (final Map<String, Object?> resourceSpans in _list(export['resourceSpans'])) {
    final Map<String, Object?> resource = _attributes(
      _jsonObject(resourceSpans['resource'] ?? const <String, Object?>{})['attributes'],
    );
    for (final Map<String, Object?> scopeSpans in _list(resourceSpans['scopeSpans'])) {
      for (final Map<String, Object?> span in _list(scopeSpans['spans'])) {
        final Map<String, Object?> attributes = _attributes(span['attributes']);
        final String traceId = _hexId(span['traceId']);
        final String spanId = _hexId(span['spanId']);
        final String name = _string(span['name']) ?? 'span';
        final List<Map<String, Object?>> events = _list(span['events']);
        bool reported = false;
        for (var i = 0; i < events.length; i++) {
          final Map<String, Object?> event = events[i];
          if (_string(event['name']) != 'exception') continue;
          final Map<String, Object?> e = _attributes(event['attributes']);
          reported = true;
          captures.add(_capture(
            idParts: <String>['trace', traceId, spanId, '$i'],
            resource: resource,
            attributes: attributes,
            operation: name,
            errorType: _string(e['exception.type']) ?? 'Exception',
            message: _string(e['exception.message']) ?? '',
            stack: _string(e['exception.stacktrace']) ?? '',
            // `exception.escaped` true: it left the span's scope uncaught.
            handled: e['exception.escaped'] != true,
            severity: 'serious',
            occurredAtNanos: _nanos(event['timeUnixNano']) ?? _nanos(span['endTimeUnixNano']),
            traceId: traceId,
            spanId: spanId,
            durationMs: _durationMs(span),
          ));
        }
        final Map<String, Object?> status = _jsonObject(span['status'] ?? const <String, Object?>{});
        if (!reported && _statusIsError(status['code'])) {
          final String message = _string(status['message']) ?? '';
          captures.add(_capture(
            idParts: <String>['trace', traceId, spanId, 'status'],
            resource: resource,
            attributes: attributes,
            operation: name,
            errorType: 'SpanError',
            message: message.isEmpty ? '$name failed' : message,
            stack: '',
            handled: false,
            severity: 'serious',
            occurredAtNanos: _nanos(span['endTimeUnixNano']),
            traceId: traceId,
            spanId: spanId,
            durationMs: _durationMs(span),
          ));
        }
      }
    }
  }
  return captures;
}

List<Map<String, Object?>> _fromLogs(Map<String, Object?> export) {
  final List<Map<String, Object?>> captures = <Map<String, Object?>>[];
  for (final Map<String, Object?> resourceLogs in _list(export['resourceLogs'])) {
    final Map<String, Object?> resource = _attributes(
      _jsonObject(resourceLogs['resource'] ?? const <String, Object?>{})['attributes'],
    );
    var index = 0;
    for (final Map<String, Object?> scopeLogs in _list(resourceLogs['scopeLogs'])) {
      for (final Map<String, Object?> record in _list(scopeLogs['logRecords'])) {
        index++;
        final int severity = _int(record['severityNumber']) ?? 0;
        // 17–24 are ERROR and FATAL in the OTLP severity scale.
        if (severity < 17) continue;
        final Map<String, Object?> attributes = _attributes(record['attributes']);
        final Object? body = _anyValue(record['body']);
        final String bodyText = body is String ? body : (body == null ? '' : jsonEncode(body));
        final String traceId = _hexId(record['traceId']);
        final String spanId = _hexId(record['spanId']);
        // 0 is OTLP's "not set"; the collector's observed time stands in.
        final int? set = _nanos(record['timeUnixNano']);
        final int? time = set == null || set == 0 ? _nanos(record['observedTimeUnixNano']) : set;
        captures.add(_capture(
          idParts: <String>[
            'log',
            traceId,
            spanId,
            '${time ?? 0}',
            '$index',
            sha1.convert(utf8.encode(bodyText)).toString(),
          ],
          resource: resource,
          attributes: attributes,
          // `code.function.name` is the current semantic convention (the
          // Python SDK writes it); `code.function` the older one.
          operation: _string(attributes['code.function.name']) ??
              _string(attributes['code.function']) ??
              _string(record['severityText'])?.toLowerCase() ??
              'log',
          errorType: _string(attributes['exception.type']) ?? 'LogError',
          message: _string(attributes['exception.message']) ?? bodyText,
          stack: _string(attributes['exception.stacktrace']) ?? '',
          handled: true,
          severity: severity >= 21 ? 'critical' : 'serious',
          occurredAtNanos: time,
          traceId: traceId,
          spanId: spanId,
          durationMs: null,
        ));
      }
    }
  }
  return captures;
}

Map<String, Object?> _capture({
  required List<String> idParts,
  required Map<String, Object?> resource,
  required Map<String, Object?> attributes,
  required String operation,
  required String errorType,
  required String message,
  required String stack,
  required bool handled,
  required String severity,
  required int? occurredAtNanos,
  required String traceId,
  required String spanId,
  required int? durationMs,
}) {
  final String service = _string(resource['service.name']) ?? 'otlp';
  final String? language = _string(resource['telemetry.sdk.language']);
  final String runtime = <String?>[
    _string(resource['process.runtime.name']),
    _string(resource['process.runtime.version']),
  ].whereType<String>().join(' ');
  final Map<String, Object?> request = <String, Object?>{
    if (_string(attributes['http.request.method'] ?? attributes['http.method']) case final String m)
      'method': m.toUpperCase(),
    if (_string(attributes['http.route']) case final String r) 'route': r,
    if (_string(attributes['url.path']) ?? _pathOf(_string(attributes['http.target']))
        case final String p)
      'path': p,
    if (_int(attributes['http.response.status_code'] ?? attributes['http.status_code']) case final int s)
      'status': s,
    'durationMs': ?durationMs,
  };
  final DateTime occurredAt = occurredAtNanos == null || occurredAtNanos <= 0
      ? DateTime.now().toUtc()
      : DateTime.fromMicrosecondsSinceEpoch(occurredAtNanos ~/ 1000, isUtc: true);
  return <String, Object?>{
    'captureId': sha1.convert(utf8.encode(idParts.join('|'))).toString(),
    'occurredAt': occurredAt.toIso8601String(),
    'source': 'otlp',
    'severity': severity,
    'category': 'exception',
    'feature': service,
    'operation': operation.isEmpty ? 'span' : operation,
    'message': message,
    'errorType': errorType,
    'stackTrace': stack,
    // A trace is the nearest thing a server has to a session: every capture
    // from one request shares it.
    'sessionId': traceId.isNotEmpty
        ? traceId
        : 'otlp-${_string(resource['service.instance.id']) ?? service}',
    'handled': handled,
    if (_string(resource['service.version']) case final String v) 'appVersion': v,
    if (_string(resource['deployment.environment.name'] ?? resource['deployment.environment'])
        case final String env)
      'environment': env,
    'context': <String, Object?>{
      'service': service,
      'language': ?language,
      if (runtime.isNotEmpty) 'runtime': runtime,
      if (_string(resource['host.name']) case final String h) 'host': h,
      if (request.isNotEmpty) 'request': request,
      if (traceId.isNotEmpty) 'traceId': traceId,
      if (spanId.isNotEmpty) 'spanId': spanId,
    },
    'tags': <String, Object?>{},
    'breadcrumbs': const <Object?>[],
  };
}

String? _pathOf(String? target) => target?.split('?').first.split('#').first;

int? _durationMs(Map<String, Object?> span) {
  final int? start = _nanos(span['startTimeUnixNano']);
  final int? end = _nanos(span['endTimeUnixNano']);
  if (start == null || end == null || end < start) return null;
  return (end - start) ~/ 1000000;
}

bool _statusIsError(Object? code) =>
    code == 2 || code == '2' || code == 'STATUS_CODE_ERROR';

// ------------------------------------------------------ OTLP/JSON helpers

Map<String, Object?> _jsonObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('expected an object');
}

List<Map<String, Object?>> _list(Object? value) => <Map<String, Object?>>[
  if (value is List)
    for (final Object? item in value)
      if (item is Map) _jsonObject(item),
];

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

int? _int(Object? value) => switch (value) {
  final int v => v,
  final double v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

/// OTLP/JSON writes 64-bit integers as strings or numbers; protobuf gives ints.
int? _nanos(Object? value) => _int(value);

/// Trace and span ids: hex in OTLP/JSON (and here, from protobuf bytes).
String _hexId(Object? value) {
  final String? text = _string(value);
  if (text == null) return '';
  final String lower = text.toLowerCase();
  if (RegExp(r'^[0-9a-f]+$').hasMatch(lower)) {
    return RegExp(r'^0+$').hasMatch(lower) ? '' : lower;
  }
  // Some JSON encoders write the bytes base64, as protobuf's JSON mapping would.
  try {
    final String hex = base64.decode(text).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return RegExp(r'^0+$').hasMatch(hex) ? '' : hex;
  } on FormatException {
    return '';
  }
}

Map<String, Object?> _attributes(Object? value) => <String, Object?>{
  for (final Map<String, Object?> kv in _list(value))
    if (_string(kv['key']) case final String key) key: _anyValue(kv['value']),
};

Object? _anyValue(Object? value) {
  if (value is! Map) return null;
  final Map<String, Object?> v = _jsonObject(value);
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('boolValue')) return v['boolValue'];
  if (v.containsKey('intValue')) return _int(v['intValue']);
  if (v.containsKey('doubleValue')) {
    final Object? d = v['doubleValue'];
    return d is num ? d.toDouble() : double.tryParse('$d');
  }
  if (v.containsKey('arrayValue')) {
    return <Object?>[
      for (final Map<String, Object?> item in _list(_jsonObject(v['arrayValue'] ?? const <String, Object?>{})['values']))
        _anyValue(item),
    ];
  }
  if (v.containsKey('kvlistValue')) {
    return _attributes(_jsonObject(v['kvlistValue'] ?? const <String, Object?>{})['values']);
  }
  if (v.containsKey('bytesValue')) return v['bytesValue'];
  return null;
}

// --------------------------------------------------------------- protobuf
//
// A reader for exactly the OTLP messages used here, written to the field
// numbers in opentelemetry-proto (collector/{trace,logs}/v1, trace/v1,
// logs/v1, common/v1, resource/v1). It builds the same maps OTLP/JSON
// decodes to, so one mapping serves both encodings. Unknown fields are
// skipped by wire type, as protobuf requires.

final class _Proto {
  _Proto(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  bool get done => _at >= _bytes.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_at >= _bytes.length) throw const FormatException('truncated varint');
      final int b = _bytes[_at++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
  }

  ({int field, int wire}) tag() {
    final int t = varint();
    return (field: t >> 3, wire: t & 7);
  }

  Uint8List bytes() {
    final int length = varint();
    if (length < 0 || _at + length > _bytes.length) throw const FormatException('truncated field');
    final Uint8List out = Uint8List.sublistView(_bytes, _at, _at + length);
    _at += length;
    return out;
  }

  int fixed64() {
    if (_at + 8 > _bytes.length) throw const FormatException('truncated fixed64');
    final int v = _data.getUint64(_at, Endian.little);
    _at += 8;
    return v;
  }

  double double64() {
    if (_at + 8 > _bytes.length) throw const FormatException('truncated double');
    final double v = _data.getFloat64(_at, Endian.little);
    _at += 8;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _at += 8;
      case 2:
        bytes();
      case 5:
        _at += 4;
      default:
        throw FormatException('unsupported wire type $wire');
    }
    if (_at > _bytes.length) throw const FormatException('truncated');
  }
}

typedef _Fields = void Function(_Proto p, int field, int wire);

void _read(Uint8List bytes, _Fields onField) {
  final _Proto p = _Proto(bytes);
  while (!p.done) {
    final ({int field, int wire}) t = p.tag();
    onField(p, t.field, t.wire);
  }
}

String _utf8(Uint8List b) => utf8.decode(b, allowMalformed: true);
String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Map<String, Object?> _decodeTraceExport(Uint8List bytes) {
  final List<Object?> resourceSpans = <Object?>[];
  _read(bytes, (p, f, w) => f == 1 && w == 2 ? resourceSpans.add(_resourceSpans(p.bytes())) : p.skip(w));
  return <String, Object?>{'resourceSpans': resourceSpans};
}

Map<String, Object?> _decodeLogsExport(Uint8List bytes) {
  final List<Object?> resourceLogs = <Object?>[];
  _read(bytes, (p, f, w) => f == 1 && w == 2 ? resourceLogs.add(_resourceLogs(p.bytes())) : p.skip(w));
  return <String, Object?>{'resourceLogs': resourceLogs};
}

Map<String, Object?> _resource(Uint8List bytes) {
  final List<Object?> attributes = <Object?>[];
  _read(bytes, (p, f, w) => f == 1 && w == 2 ? attributes.add(_keyValue(p.bytes())) : p.skip(w));
  return <String, Object?>{'attributes': attributes};
}

Map<String, Object?> _resourceSpans(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{'scopeSpans': <Object?>[]};
  _read(bytes, (p, f, w) {
    if (f == 1 && w == 2) {
      out['resource'] = _resource(p.bytes());
    } else if (f == 2 && w == 2) {
      (out['scopeSpans']! as List<Object?>).add(_scopeSpans(p.bytes()));
    } else {
      p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _scopeSpans(Uint8List bytes) {
  final List<Object?> spans = <Object?>[];
  _read(bytes, (p, f, w) => f == 2 && w == 2 ? spans.add(_span(p.bytes())) : p.skip(w));
  return <String, Object?>{'spans': spans};
}

Map<String, Object?> _span(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{'attributes': <Object?>[], 'events': <Object?>[]};
  _read(bytes, (p, f, w) {
    switch ((f, w)) {
      case (1, 2):
        out['traceId'] = _hex(p.bytes());
      case (2, 2):
        out['spanId'] = _hex(p.bytes());
      case (5, 2):
        out['name'] = _utf8(p.bytes());
      case (6, 0):
        out['kind'] = p.varint();
      case (7, 1):
        out['startTimeUnixNano'] = p.fixed64();
      case (8, 1):
        out['endTimeUnixNano'] = p.fixed64();
      case (9, 2):
        (out['attributes']! as List<Object?>).add(_keyValue(p.bytes()));
      case (11, 2):
        (out['events']! as List<Object?>).add(_event(p.bytes()));
      case (15, 2):
        out['status'] = _status(p.bytes());
      default:
        p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _event(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{'attributes': <Object?>[]};
  _read(bytes, (p, f, w) {
    switch ((f, w)) {
      case (1, 1):
        out['timeUnixNano'] = p.fixed64();
      case (2, 2):
        out['name'] = _utf8(p.bytes());
      case (3, 2):
        (out['attributes']! as List<Object?>).add(_keyValue(p.bytes()));
      default:
        p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _status(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{};
  _read(bytes, (p, f, w) {
    switch ((f, w)) {
      case (2, 2):
        out['message'] = _utf8(p.bytes());
      case (3, 0):
        out['code'] = p.varint();
      default:
        p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _resourceLogs(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{'scopeLogs': <Object?>[]};
  _read(bytes, (p, f, w) {
    if (f == 1 && w == 2) {
      out['resource'] = _resource(p.bytes());
    } else if (f == 2 && w == 2) {
      (out['scopeLogs']! as List<Object?>).add(_scopeLogs(p.bytes()));
    } else {
      p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _scopeLogs(Uint8List bytes) {
  final List<Object?> records = <Object?>[];
  _read(bytes, (p, f, w) => f == 2 && w == 2 ? records.add(_logRecord(p.bytes())) : p.skip(w));
  return <String, Object?>{'logRecords': records};
}

Map<String, Object?> _logRecord(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{'attributes': <Object?>[]};
  _read(bytes, (p, f, w) {
    switch ((f, w)) {
      case (1, 1):
        out['timeUnixNano'] = p.fixed64();
      case (2, 0):
        out['severityNumber'] = p.varint();
      case (3, 2):
        out['severityText'] = _utf8(p.bytes());
      case (5, 2):
        out['body'] = _anyValueProto(p.bytes());
      case (6, 2):
        (out['attributes']! as List<Object?>).add(_keyValue(p.bytes()));
      case (9, 2):
        out['traceId'] = _hex(p.bytes());
      case (10, 2):
        out['spanId'] = _hex(p.bytes());
      case (11, 1):
        out['observedTimeUnixNano'] = p.fixed64();
      default:
        p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _keyValue(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{};
  _read(bytes, (p, f, w) {
    switch ((f, w)) {
      case (1, 2):
        out['key'] = _utf8(p.bytes());
      case (2, 2):
        out['value'] = _anyValueProto(p.bytes());
      default:
        p.skip(w);
    }
  });
  return out;
}

Map<String, Object?> _anyValueProto(Uint8List bytes) {
  final Map<String, Object?> out = <String, Object?>{};
  _read(bytes, (p, f, w) {
    switch ((f, w)) {
      case (1, 2):
        out['stringValue'] = _utf8(p.bytes());
      case (2, 0):
        out['boolValue'] = p.varint() != 0;
      case (3, 0):
        out['intValue'] = p.varint();
      case (4, 1):
        out['doubleValue'] = p.double64();
      case (5, 2):
        final List<Object?> values = <Object?>[];
        _read(p.bytes(), (q, g, x) => g == 1 && x == 2 ? values.add(_anyValueProto(q.bytes())) : q.skip(x));
        out['arrayValue'] = <String, Object?>{'values': values};
      case (6, 2):
        final List<Object?> values = <Object?>[];
        _read(p.bytes(), (q, g, x) => g == 1 && x == 2 ? values.add(_keyValue(q.bytes())) : q.skip(x));
        out['kvlistValue'] = <String, Object?>{'values': values};
      case (7, 2):
        out['bytesValue'] = base64.encode(p.bytes());
      default:
        p.skip(w);
    }
  });
  return out;
}
