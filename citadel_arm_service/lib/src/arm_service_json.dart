import 'dart:convert';

import 'arm_service_models.dart';

String encodeArmPageToken(ArmPageCursor cursor) {
  final payload = jsonEncode(<String, Object?>{
    'timestamp': _utc(cursor.timestamp).toIso8601String(),
    'documentId': cursor.documentId,
  });
  return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
}

ArmPageCursor decodeArmPageToken(String value) {
  final token = value.trim();
  if (token.isEmpty || token.length > 1024 || token != value) {
    throw const FormatException('pageToken is invalid.');
  }
  try {
    final normalized = token.padRight((token.length + 3) ~/ 4 * 4, '=');
    final json = _object(
      jsonDecode(utf8.decode(base64Url.decode(normalized))),
      r'$',
    );
    _keys(
      json,
      required: const <String>{'timestamp', 'documentId'},
      path: r'$',
    );
    return ArmPageCursor(
      timestamp: _dateTime(json['timestamp'], r'$.timestamp'),
      documentId: _resourceId(json['documentId'], r'$.documentId'),
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('pageToken is invalid.');
  }
}

Map<String, Object?> encodeArmIssueRecord(ArmIssueRecord value) {
  return <String, Object?>{
    'issueId': value.issueId,
    'severity': value.severity,
    'category': value.category,
    'feature': value.feature,
    'operation': value.operation,
    'firstSeenAt': _utc(value.firstSeenAt).toIso8601String(),
    'lastSeenAt': _utc(value.lastSeenAt).toIso8601String(),
    'caseCount': value.caseCount,
    if (value.firstCaseId != null) 'firstCaseId': value.firstCaseId,
    if (value.lastCaseId != null) 'lastCaseId': value.lastCaseId,
    if (value.status != null) 'status': _issueStatusWire(value.status!),
    if (value.appVersion != null) 'appVersion': value.appVersion,
    if (value.buildNumber != null) 'buildNumber': value.buildNumber,
    if (value.releaseChannel != null) 'releaseChannel': value.releaseChannel,
  };
}

ArmIssueRecord decodeArmIssueRecord(Object? value) =>
    decodeArmIssueRecordAt(value, r'$');

ArmIssueRecord decodeArmIssueRecordAt(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{
      'issueId',
      'severity',
      'category',
      'feature',
      'operation',
      'firstSeenAt',
      'lastSeenAt',
      'caseCount',
    },
    optional: const <String>{
      'firstCaseId',
      'lastCaseId',
      'status',
      'appVersion',
      'buildNumber',
      'releaseChannel',
    },
    path: path,
  );
  final count = _int(json['caseCount'], r'$.caseCount');
  if (count < 0) {
    throw const FormatException(r'$.caseCount must not be negative.');
  }
  return ArmIssueRecord(
    issueId: _resourceId(json['issueId'], r'$.issueId'),
    severity: _nonEmptyString(json['severity'], r'$.severity'),
    category: _string(json['category'], r'$.category'),
    feature: _string(json['feature'], r'$.feature'),
    operation: _string(json['operation'], r'$.operation'),
    firstSeenAt: _dateTime(json['firstSeenAt'], r'$.firstSeenAt'),
    lastSeenAt: _dateTime(json['lastSeenAt'], r'$.lastSeenAt'),
    caseCount: count,
    firstCaseId: _optionalResourceId(json['firstCaseId'], r'$.firstCaseId'),
    lastCaseId: _optionalResourceId(json['lastCaseId'], r'$.lastCaseId'),
    status: _optionalIssueStatus(json['status'], r'$.status'),
    appVersion: _optionalString(json['appVersion'], r'$.appVersion'),
    buildNumber: _optionalString(json['buildNumber'], r'$.buildNumber'),
    releaseChannel: _optionalString(
      json['releaseChannel'],
      r'$.releaseChannel',
    ),
  );
}

Map<String, Object?> encodeArmCaseRecord(ArmCaseRecord value) {
  return <String, Object?>{
    'caseId': value.caseId,
    'issueId': value.issueId,
    'fingerprint': value.fingerprint,
    'severity': value.severity,
    'category': value.category,
    'feature': value.feature,
    'operation': value.operation,
    'message': value.message,
    'errorType': value.errorType,
    if (value.errorName != null) 'errorName': value.errorName,
    if (value.errorData != null) 'errorData': value.errorData,
    'stackTrace': value.stackTrace,
    'sessionId': value.sessionId,
    'handled': value.handled,
    'context': value.context,
    'tags': value.tags,
    'breadcrumbs': value.breadcrumbs,
    if (value.recoverySnapshot != null)
      'recoverySnapshot': value.recoverySnapshot,
    if (value.screenshot != null) 'screenshot': value.screenshot,
    if (value.status != null) 'status': _caseStatusWire(value.status!),
    if (value.appVersion != null) 'appVersion': value.appVersion,
    if (value.buildNumber != null) 'buildNumber': value.buildNumber,
    if (value.releaseChannel != null) 'releaseChannel': value.releaseChannel,
    'createdAt': _utc(value.createdAt).toIso8601String(),
  };
}

ArmCaseRecord decodeArmCaseRecord(Object? value) =>
    decodeArmCaseRecordAt(value, r'$');

ArmCaseRecord decodeArmCaseRecordAt(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{
      'caseId',
      'issueId',
      'fingerprint',
      'severity',
      'category',
      'feature',
      'operation',
      'message',
      'errorType',
      'stackTrace',
      'sessionId',
      'handled',
      'context',
      'tags',
      'breadcrumbs',
      'createdAt',
    },
    optional: const <String>{
      'errorName',
      'errorData',
      'recoverySnapshot',
      'screenshot',
      'status',
      'appVersion',
      'buildNumber',
      'releaseChannel',
    },
    path: path,
  );
  return ArmCaseRecord(
    caseId: _resourceId(json['caseId'], r'$.caseId'),
    issueId: _resourceId(json['issueId'], r'$.issueId'),
    fingerprint: _nonEmptyString(json['fingerprint'], r'$.fingerprint'),
    severity: _nonEmptyString(json['severity'], r'$.severity'),
    category: _string(json['category'], r'$.category'),
    feature: _string(json['feature'], r'$.feature'),
    operation: _string(json['operation'], r'$.operation'),
    message: _string(json['message'], r'$.message'),
    errorType: _string(json['errorType'], r'$.errorType'),
    errorName: _optionalString(json['errorName'], r'$.errorName'),
    errorData: _optionalJsonMap(json['errorData'], r'$.errorData'),
    stackTrace: _string(json['stackTrace'], r'$.stackTrace'),
    sessionId: _string(json['sessionId'], r'$.sessionId'),
    handled: _bool(json['handled'], r'$.handled'),
    context: _jsonMap(json['context'], r'$.context'),
    tags: _jsonMap(json['tags'], r'$.tags'),
    breadcrumbs: _jsonMapList(json['breadcrumbs'], r'$.breadcrumbs'),
    recoverySnapshot: _optionalJsonMap(
      json['recoverySnapshot'],
      r'$.recoverySnapshot',
    ),
    screenshot: _optionalJsonMap(json['screenshot'], r'$.screenshot'),
    status: _optionalCaseStatus(json['status'], r'$.status'),
    appVersion: _optionalString(json['appVersion'], r'$.appVersion'),
    buildNumber: _optionalString(json['buildNumber'], r'$.buildNumber'),
    releaseChannel: _optionalString(
      json['releaseChannel'],
      r'$.releaseChannel',
    ),
    createdAt: _dateTime(json['createdAt'], r'$.createdAt'),
  );
}

Map<String, Object?> encodeArmIssuePage(ArmIssuePage value) =>
    <String, Object?>{
      'projectId': value.projectId,
      'issues': value.issues.map(encodeArmIssueRecord).toList(growable: false),
      if (value.nextPageToken != null) 'nextPageToken': value.nextPageToken,
    };

ArmIssuePage decodeArmIssuePage(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'projectId', 'issues'},
    optional: const <String>{'nextPageToken', 'requestId'},
    path: r'$',
  );
  return ArmIssuePage(
    projectId: _resourceId(json['projectId'], r'$.projectId'),
    issues: _list(json['issues'], r'$.issues').indexed
        .map(
          (entry) => decodeArmIssueRecordAt(entry.$2, r'$.issues[${entry.$1}]'),
        )
        .toList(growable: false),
    nextPageToken: _optionalString(json['nextPageToken'], r'$.nextPageToken'),
  );
}

Map<String, Object?> encodeArmCasePage(ArmCasePage value) => <String, Object?>{
  'projectId': value.projectId,
  'cases': value.cases.map(encodeArmCaseRecord).toList(growable: false),
  if (value.nextPageToken != null) 'nextPageToken': value.nextPageToken,
};

ArmCasePage decodeArmCasePage(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'projectId', 'cases'},
    optional: const <String>{'nextPageToken', 'requestId'},
    path: r'$',
  );
  return ArmCasePage(
    projectId: _resourceId(json['projectId'], r'$.projectId'),
    cases: _list(json['cases'], r'$.cases').indexed
        .map(
          (entry) => decodeArmCaseRecordAt(entry.$2, r'$.cases[${entry.$1}]'),
        )
        .toList(growable: false),
    nextPageToken: _optionalString(json['nextPageToken'], r'$.nextPageToken'),
  );
}

Map<String, Object?> encodeArmCaseDetail(ArmCaseDetail value) =>
    <String, Object?>{
      'projectId': value.projectId,
      'case': encodeArmCaseRecord(value.caseRecord),
      'issue': encodeArmIssueRecord(value.issue),
    };

ArmCaseDetail decodeArmCaseDetail(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'projectId', 'case', 'issue'},
    optional: const <String>{'requestId'},
    path: r'$',
  );
  return ArmCaseDetail(
    projectId: _resourceId(json['projectId'], r'$.projectId'),
    caseRecord: decodeArmCaseRecordAt(json['case'], r'$.case'),
    issue: decodeArmIssueRecordAt(json['issue'], r'$.issue'),
  );
}

Map<String, Object?> encodeArmServiceError(ArmServiceError value) =>
    <String, Object?>{
      'code': value.code.name,
      'message': value.message,
      'requestId': value.requestId,
      'retryable': value.retryable,
      'details': value.details,
    };

ArmIssueStatusPatch decodeArmIssueStatusPatch(Object? value) {
  final json = _object(value, r'$');
  _keys(json, required: const <String>{'status'}, path: r'$');
  return ArmIssueStatusPatch(status: _issueStatus(json['status'], r'$.status'));
}

ArmCaseStatusPatch decodeArmCaseStatusPatch(Object? value) {
  final json = _object(value, r'$');
  _keys(json, required: const <String>{'status'}, path: r'$');
  return ArmCaseStatusPatch(status: _caseStatus(json['status'], r'$.status'));
}

String armIssueStatusWireName(ArmIssueStatus value) => _issueStatusWire(value);

String armCaseStatusWireName(ArmCaseStatus value) => _caseStatusWire(value);

String validateArmResourceId(String value, {required String fieldName}) {
  return _resourceId(value, fieldName);
}

DateTime parseArmUtcTimestamp(String value, {required String fieldName}) {
  return _dateTime(value, fieldName);
}

String _issueStatusWire(ArmIssueStatus value) => value.name;

String _caseStatusWire(ArmCaseStatus value) => switch (value) {
  ArmCaseStatus.newCase => 'new',
  _ => value.name,
};

ArmIssueStatus _issueStatus(Object? value, String path) {
  final text = _nonEmptyString(value, path);
  return ArmIssueStatus.values.firstWhere(
    (status) => _issueStatusWire(status) == text,
    orElse: () => throw FormatException('$path has an unsupported status.'),
  );
}

ArmCaseStatus _caseStatus(Object? value, String path) {
  final text = _nonEmptyString(value, path);
  return ArmCaseStatus.values.firstWhere(
    (status) => _caseStatusWire(status) == text,
    orElse: () => throw FormatException('$path has an unsupported status.'),
  );
}

ArmIssueStatus? _optionalIssueStatus(Object? value, String path) =>
    value == null ? null : _issueStatus(value, path);

ArmCaseStatus? _optionalCaseStatus(Object? value, String path) =>
    value == null ? null : _caseStatus(value, path);

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$path must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings.');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

void _keys(
  Map<String, Object?> value, {
  required Set<String> required,
  Set<String> optional = const <String>{},
  required String path,
}) {
  for (final key in required) {
    if (!value.containsKey(key)) {
      throw FormatException('$path.$key is required.');
    }
  }
  final allowed = <String>{...required, ...optional};
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path.$key is not supported.');
    }
  }
}

String _resourceId(Object? value, String path) {
  final text = _nonEmptyString(value, path);
  if (text.length > 128 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(text)) {
    throw FormatException('$path is not a valid resource identifier.');
  }
  return text;
}

String? _optionalResourceId(Object? value, String path) =>
    value == null ? null : _resourceId(value, path);

String _string(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string.');
  }
  return value;
}

String _nonEmptyString(Object? value, String path) {
  final text = _string(value, path);
  if (text.isEmpty || text.trim() != text) {
    throw FormatException('$path must be a non-empty, trimmed string.');
  }
  return text;
}

String? _optionalString(Object? value, String path) =>
    value == null ? null : _nonEmptyString(value, path);

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be an array.');
  }
  return value;
}

int _int(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer.');
  }
  return value;
}

bool _bool(Object? value, String path) {
  if (value is! bool) {
    throw FormatException('$path must be a boolean.');
  }
  return value;
}

DateTime _dateTime(Object? value, String path) {
  final text = _nonEmptyString(value, path);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc || !text.endsWith('Z')) {
    throw FormatException('$path must be an ISO-8601 UTC timestamp.');
  }
  return parsed;
}

DateTime _utc(DateTime value) => value.toUtc();

Map<String, Object?> _jsonMap(Object? value, String path) {
  final map = _object(value, path);
  _validateJsonValue(map, path);
  return map;
}

Map<String, Object?>? _optionalJsonMap(Object? value, String path) =>
    value == null ? null : _jsonMap(value, path);

List<Map<String, Object?>> _jsonMapList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be an array.');
  }
  return value.indexed
      .map((entry) => _jsonMap(entry.$2, '$path[${entry.$1}]'))
      .toList(growable: false);
}

void _validateJsonValue(Object? value, String path) {
  if (value == null || value is String || value is num || value is bool) {
    return;
  }
  if (value is List<Object?>) {
    for (final entry in value.indexed) {
      _validateJsonValue(entry.$2, '$path[${entry.$1}]');
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _validateJsonValue(entry.value, '$path.${entry.key}');
    }
    return;
  }
  throw FormatException('$path must contain JSON-compatible values.');
}
