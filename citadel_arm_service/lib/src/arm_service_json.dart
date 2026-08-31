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
    'tags': value.tags,
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
      'tags',
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
    tags: armNormalizedTags(json['tags'], r'$.tags'),
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
    if (value.operatorSeverity != null)
      'operatorSeverity': value.operatorSeverity,
    if (value.severityUpdatedBy != null)
      'severityUpdatedBy': value.severityUpdatedBy,
    if (value.severityUpdatedAt != null)
      'severityUpdatedAt': _utc(value.severityUpdatedAt!).toIso8601String(),
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
      'operatorSeverity',
      'severityUpdatedBy',
      'severityUpdatedAt',
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
    operatorSeverity: _optionalString(
      json['operatorSeverity'],
      r'$.operatorSeverity',
    ),
    severityUpdatedBy: _optionalString(
      json['severityUpdatedBy'],
      r'$.severityUpdatedBy',
    ),
    severityUpdatedAt: json['severityUpdatedAt'] == null
        ? null
        : _dateTime(json['severityUpdatedAt'], r'$.severityUpdatedAt'),
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

ArmCaseSeverityPatch decodeArmCaseSeverityPatch(Object? value) {
  final json = _object(value, r'$');
  _keys(json, required: const <String>{'severity'}, path: r'$');
  return ArmCaseSeverityPatch(
    severity: _severity(json['severity'], r'$.severity'),
  );
}

ArmIssueTagsPatch decodeArmIssueTagsPatch(Object? value) {
  final json = _object(value, r'$');
  _keys(json, required: const <String>{'tags'}, path: r'$');
  return ArmIssueTagsPatch(tags: armNormalizedTags(json['tags'], r'$.tags'));
}

/// How many tags one fingerprint may carry.
///
/// Bounded because tags are a triage aid, not a filing system: a fingerprint
/// with forty of them tells a reader nothing, and an unbounded list is a
/// document somebody can grow without limit.
const int armMaximumIssueTags = 24;

/// Lower-cased, trimmed, deduplicated and sorted.
///
/// Normalised on the way in rather than compared loosely on the way out, so
/// `Regression` and `regression` cannot both exist and mean the same thing —
/// and so two reads of one fingerprint produce a comparable set.
List<String> armNormalizedTags(Object? value, String path) {
  if (value == null) return const <String>[];
  if (value is! List) {
    throw FormatException('$path must be an array of strings.');
  }
  final Set<String> seen = <String>{};
  for (final Object? entry in value) {
    if (entry is! String) {
      throw FormatException('$path must contain only strings.');
    }
    final String tag = entry.trim().toLowerCase();
    if (tag.isEmpty) continue;
    if (tag.length > 48 || !RegExp(r'^[a-z0-9][a-z0-9._\- ]*$').hasMatch(tag)) {
      throw FormatException('$path contains an invalid tag: $entry');
    }
    seen.add(tag);
  }
  if (seen.length > armMaximumIssueTags) {
    throw FormatException('$path may hold at most $armMaximumIssueTags tags.');
  }
  final List<String> tags = seen.toList()..sort();
  return List<String>.unmodifiable(tags);
}

String armSeverityWireName(ArmSeverity value) => value.name;

ArmSeverity _severity(Object? value, String path) {
  final String name = _nonEmptyString(value, path).toLowerCase();
  for (final ArmSeverity severity in ArmSeverity.values) {
    if (severity.name == name) return severity;
  }
  throw FormatException('$path is not a known severity.');
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

// ---------------------------------------------------------------------------
// Alerting codecs (Feature 1.4.6)
// ---------------------------------------------------------------------------

Map<String, Object?> encodeArmPolicyRule(ArmPolicyRule value) =>
    <String, Object?>{
      'join': value.join.name,
      'field': value.field.name,
      'operator': value.operator.name,
      'value': value.value,
    };

Map<String, Object?> encodeArmPolicyRecord(ArmPolicyRecord value) =>
    <String, Object?>{
      'policyId': value.policyId,
      'displayName': value.displayName,
      'enabled': value.enabled,
      'rules': value.rules.map(encodeArmPolicyRule).toList(growable: false),
      'tags': value.tags,
      'channelIds': value.channelIds,
      if (value.updatedAt != null)
        'updatedAt': _utc(value.updatedAt!).toIso8601String(),
      if (value.updatedBy != null) 'updatedBy': value.updatedBy,
    };

Map<String, Object?> encodeArmNotificationChannel(
  ArmNotificationChannel value,
) => <String, Object?>{
  'channelId': value.channelId,
  'displayName': value.displayName,
  'type': value.type.name,
  'recipients': value.recipients,
  'enabled': value.enabled,
  if (value.lastTestedAt != null)
    'lastTestedAt': _utc(value.lastTestedAt!).toIso8601String(),
  if (value.lastTestOutcome != null) 'lastTestOutcome': value.lastTestOutcome,
  if (value.updatedAt != null)
    'updatedAt': _utc(value.updatedAt!).toIso8601String(),
  if (value.updatedBy != null) 'updatedBy': value.updatedBy,
};

Map<String, Object?> encodeArmAlertingConfiguration(
  ArmAlertingConfiguration value,
) => <String, Object?>{
  'projectId': value.projectId,
  'policies': value.policies
      .map(encodeArmPolicyRecord)
      .toList(growable: false),
  'channels': value.channels
      .map(encodeArmNotificationChannel)
      .toList(growable: false),
};

/// How many rules one policy may carry.
///
/// Bounded because every rule is evaluated against every fingerprint, and an
/// unbounded policy is a way to make ARM slow from a form.
const int armMaximumPolicyRules = 20;

/// How many recipients one channel may carry.
///
/// Bounded for a sharper reason: a channel is a fan-out, and an unbounded
/// recipient list is a way to make Citadel send a thousand messages from a
/// single fault.
const int armMaximumChannelRecipients = 50;

ArmPolicyRule decodeArmPolicyRule(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{'field', 'operator', 'value'},
    optional: const <String>{'join'},
    path: path,
  );
  return ArmPolicyRule(
    join: _enumOf(
      ArmPolicyJoin.values,
      json['join'] ?? 'and',
      '$path.join',
    ),
    field: _enumOf(ArmPolicyField.values, json['field'], '$path.field'),
    operator: _enumOf(
      ArmPolicyOperator.values,
      json['operator'],
      '$path.operator',
    ),
    value: _boundedText(json['value'], '$path.value', 200),
  );
}

ArmPolicyRecord decodeArmPolicyRecord(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{'policyId', 'displayName', 'rules'},
    optional: const <String>{
      'enabled',
      'tags',
      'channelIds',
      'updatedAt',
      'updatedBy',
    },
    path: path,
  );
  final rules = _list(json['rules'], '$path.rules');
  if (rules.isEmpty) {
    // A policy with no rules matches every fingerprint, which is never what
    // anybody meant and is the fastest way to tag an entire project.
    throw FormatException('$path.rules must hold at least one rule.');
  }
  if (rules.length > armMaximumPolicyRules) {
    throw FormatException(
      '$path.rules may hold at most $armMaximumPolicyRules rules.',
    );
  }
  return ArmPolicyRecord(
    policyId: _resourceId(json['policyId'], '$path.policyId'),
    displayName: _boundedText(json['displayName'], '$path.displayName', 120),
    enabled: json['enabled'] == null
        ? true
        : _bool(json['enabled'], '$path.enabled'),
    rules: <ArmPolicyRule>[
      for (int index = 0; index < rules.length; index += 1)
        decodeArmPolicyRule(rules[index], '$path.rules[$index]'),
    ],
    tags: armNormalizedTags(json['tags'], '$path.tags'),
    channelIds: _resourceIdList(json['channelIds'], '$path.channelIds'),
    updatedAt: json['updatedAt'] == null
        ? null
        : _dateTime(json['updatedAt'], '$path.updatedAt'),
    updatedBy: _optionalString(json['updatedBy'], '$path.updatedBy'),
  );
}

ArmNotificationChannel decodeArmNotificationChannel(
  Object? value,
  String path,
) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{'channelId', 'displayName', 'type'},
    optional: const <String>{
      'recipients',
      'enabled',
      'lastTestedAt',
      'lastTestOutcome',
      'updatedAt',
      'updatedBy',
    },
    path: path,
  );
  final type = _enumOf(ArmChannelType.values, json['type'], '$path.type');
  final recipients = _recipients(json['recipients'], '$path.recipients', type);
  return ArmNotificationChannel(
    channelId: _resourceId(json['channelId'], '$path.channelId'),
    displayName: _boundedText(json['displayName'], '$path.displayName', 120),
    type: type,
    recipients: recipients,
    enabled: json['enabled'] == null
        ? true
        : _bool(json['enabled'], '$path.enabled'),
    lastTestedAt: json['lastTestedAt'] == null
        ? null
        : _dateTime(json['lastTestedAt'], '$path.lastTestedAt'),
    lastTestOutcome: _optionalString(
      json['lastTestOutcome'],
      '$path.lastTestOutcome',
    ),
    updatedAt: json['updatedAt'] == null
        ? null
        : _dateTime(json['updatedAt'], '$path.updatedAt'),
    updatedBy: _optionalString(json['updatedBy'], '$path.updatedBy'),
  );
}

ArmAlertingConfiguration decodeArmAlertingConfiguration(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'projectId'},
    optional: const <String>{'policies', 'channels', 'requestId'},
    path: r'$',
  );
  final policies = _list(json['policies'] ?? const <Object?>[], r'$.policies');
  final channels = _list(json['channels'] ?? const <Object?>[], r'$.channels');
  return ArmAlertingConfiguration(
    projectId: _resourceId(json['projectId'], r'$.projectId'),
    policies: <ArmPolicyRecord>[
      for (int i = 0; i < policies.length; i += 1)
        decodeArmPolicyRecord(policies[i], '\$.policies[$i]'),
    ],
    channels: <ArmNotificationChannel>[
      for (int i = 0; i < channels.length; i += 1)
        decodeArmNotificationChannel(channels[i], '\$.channels[$i]'),
    ],
  );
}

/// Recipients, validated against the channel that will send to them.
///
/// A malformed recipient is a notification nobody receives and nobody knows
/// was not received, which is the worst failure an alerting system has. So the
/// shape is checked here rather than discovered at send time.
List<String> _recipients(Object? value, String path, ArmChannelType type) {
  if (value == null) return const <String>[];
  final entries = _list(value, path);
  if (entries.length > armMaximumChannelRecipients) {
    throw FormatException(
      '$path may hold at most $armMaximumChannelRecipients recipients.',
    );
  }
  final Set<String> recipients = <String>{};
  for (final Object? entry in entries) {
    final String recipient = _nonEmptyString(entry, path).trim();
    switch (type) {
      case ArmChannelType.email:
        if (!RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(recipient)) {
          throw FormatException('$path holds an invalid email address.');
        }
        recipients.add(recipient.toLowerCase());
      case ArmChannelType.whatsApp:
        if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(recipient)) {
          throw FormatException('$path holds an invalid E.164 number.');
        }
        recipients.add(recipient);
      case ArmChannelType.webhook:
        final Uri? url = Uri.tryParse(recipient);
        // HTTPS only. A webhook over plain HTTP carries a fault report,
        // sometimes with a stack trace in it, across the open internet.
        if (url == null || url.scheme != 'https' || !url.hasAuthority) {
          throw FormatException('$path must be an https URL.');
        }
        recipients.add(recipient);
    }
  }
  if (type == ArmChannelType.webhook && recipients.length > 1) {
    throw FormatException('$path may name one webhook URL.');
  }
  return List<String>.unmodifiable(recipients.toList()..sort());
}

T _enumOf<T extends Enum>(List<T> values, Object? value, String path) {
  final String name = _nonEmptyString(value, path);
  for (final T candidate in values) {
    if (candidate.name == name) return candidate;
  }
  throw FormatException('$path is not a recognised value.');
}

String _boundedText(Object? value, String path, int maximum) {
  final String text = _nonEmptyString(value, path).trim();
  if (text.isEmpty || text.length > maximum) {
    throw FormatException('$path must be 1 to $maximum characters.');
  }
  return text;
}

List<String> _resourceIdList(Object? value, String path) {
  if (value == null) return const <String>[];
  final entries = _list(value, path);
  final Set<String> ids = <String>{
    for (final Object? entry in entries) _resourceId(entry, path),
  };
  return List<String>.unmodifiable(ids.toList()..sort());
}

Map<String, Object?> encodeArmChannelTestOutcome(ArmChannelTestOutcome value) =>
    <String, Object?>{
      'channelId': value.channelId,
      'delivered': value.delivered,
      'testedAt': _utc(value.testedAt).toIso8601String(),
      'reached': value.reached,
      if (value.reason != null) 'reason': value.reason,
    };

ArmChannelTestOutcome decodeArmChannelTestOutcome(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'channelId', 'delivered', 'testedAt'},
    optional: const <String>{'reached', 'reason', 'projectId', 'requestId'},
    path: r'$',
  );
  return ArmChannelTestOutcome(
    channelId: _resourceId(json['channelId'], r'$.channelId'),
    delivered: _bool(json['delivered'], r'$.delivered'),
    testedAt: _dateTime(json['testedAt'], r'$.testedAt'),
    reached: <String>[
      for (final Object? entry
          in _list(json['reached'] ?? const <Object?>[], r'$.reached'))
        _nonEmptyString(entry, r'$.reached'),
    ],
    reason: _optionalString(json['reason'], r'$.reason'),
  );
}

// ---------------------------------------------------------------------------
// Ticket codecs (Feature 1.5)
// ---------------------------------------------------------------------------

/// How long one history entry may be.
///
/// Bounded because the whole history is read as one document: an unbounded
/// entry is a way to make every read of a ticket expensive from a text box.
const int armMaximumTicketUpdateBody = 20000;

/// How many entries a ticket's history may hold.
///
/// A ticket that has run to this length is a conversation that should have
/// become something else. Refusing is honest; silently dropping the oldest
/// entries would lose the thing a ticket exists to keep.
const int armMaximumTicketUpdates = 500;

/// How many files may hang off a ticket or one of its entries.
const int armMaximumTicketAttachments = 20;

/// How many addresses may hold a ticket open.
const int armMaximumTicketAllowlist = 25;

/// How many case logs one ticket may name.
const int armMaximumTicketCases = 50;

Map<String, Object?> encodeArmTicketAttachment(ArmTicketAttachment value) =>
    <String, Object?>{
      'attachmentId': value.attachmentId,
      'fileName': value.fileName,
      'contentType': value.contentType,
      'sizeBytes': value.sizeBytes,
      // Omitted rather than nulled when it is absent, so a redacted view is
      // not a document with a hole where a path used to be.
      if (value.storagePath case final String path) 'storagePath': path,
    };

ArmTicketAttachment decodeArmTicketAttachment(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{
      'attachmentId',
      'fileName',
      'contentType',
      'sizeBytes',
    },
    optional: const <String>{'storagePath'},
    path: path,
  );
  final int size = _int(json['sizeBytes'], '$path.sizeBytes');
  if (size < 0) {
    throw FormatException('$path.sizeBytes must not be negative.');
  }
  return ArmTicketAttachment(
    attachmentId: _resourceId(json['attachmentId'], '$path.attachmentId'),
    fileName: _boundedText(json['fileName'], '$path.fileName', 255),
    contentType: _boundedText(json['contentType'], '$path.contentType', 120),
    sizeBytes: size,
    storagePath: json['storagePath'] == null
        ? null
        : _boundedText(json['storagePath'], '$path.storagePath', 1024),
  );
}

List<ArmTicketAttachment> _ticketAttachments(Object? value, String path) {
  if (value == null) return const <ArmTicketAttachment>[];
  final entries = _list(value, path);
  if (entries.length > armMaximumTicketAttachments) {
    throw FormatException(
      '$path may hold at most $armMaximumTicketAttachments attachments.',
    );
  }
  return <ArmTicketAttachment>[
    for (int index = 0; index < entries.length; index += 1)
      decodeArmTicketAttachment(entries[index], '$path[$index]'),
  ];
}

/// Addresses, lower-cased, deduplicated and sorted.
///
/// Normalised for the same reason tags are: `Ops@x` and `ops@x` are one person
/// and an allowlist that held both would be answering a question about
/// capitalisation.
List<String> armNormalizedAllowlist(Object? value, String path) {
  if (value == null) return const <String>[];
  final entries = _list(value, path);
  if (entries.length > armMaximumTicketAllowlist) {
    throw FormatException(
      '$path may hold at most $armMaximumTicketAllowlist addresses.',
    );
  }
  final Set<String> addresses = <String>{};
  for (final Object? entry in entries) {
    final String address = _nonEmptyString(entry, path).trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(address)) {
      throw FormatException('$path holds an invalid email address.');
    }
    addresses.add(address);
  }
  return List<String>.unmodifiable(addresses.toList()..sort());
}

Map<String, Object?> encodeArmTicketUpdate(ArmTicketUpdate value) =>
    <String, Object?>{
      'updateId': value.updateId,
      'authorKind': value.authorKind.name,
      'authorLabel': value.authorLabel,
      'body': value.body,
      'createdAt': _utc(value.createdAt).toIso8601String(),
      'attachments': value.attachments
          .map(encodeArmTicketAttachment)
          .toList(growable: false),
    };

ArmTicketUpdate decodeArmTicketUpdate(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{
      'updateId',
      'authorKind',
      'authorLabel',
      'body',
      'createdAt',
    },
    optional: const <String>{'attachments'},
    path: path,
  );
  return ArmTicketUpdate(
    updateId: _resourceId(json['updateId'], '$path.updateId'),
    authorKind: _enumOf(
      ArmTicketAuthorKind.values,
      json['authorKind'],
      '$path.authorKind',
    ),
    authorLabel: _boundedText(json['authorLabel'], '$path.authorLabel', 320),
    body: _boundedText(json['body'], '$path.body', armMaximumTicketUpdateBody),
    createdAt: _dateTime(json['createdAt'], '$path.createdAt'),
    attachments: _ticketAttachments(json['attachments'], '$path.attachments'),
  );
}

Map<String, Object?> encodeArmTicketRecord(ArmTicketRecord value) =>
    <String, Object?>{
      'ticketId': value.ticketId,
      'title': value.title,
      'description': value.description,
      'status': value.status.name,
      'createdAt': _utc(value.createdAt).toIso8601String(),
      'updatedAt': _utc(value.updatedAt).toIso8601String(),
      'createdBy': value.createdBy,
      if (value.reporterContact != null)
        'reporterContact': value.reporterContact,
      'caseIds': value.caseIds,
      if (value.issueId != null) 'issueId': value.issueId,
      if (value.sessionId != null) 'sessionId': value.sessionId,
      'allowlist': value.allowlist,
      'updates': value.updates
          .map(encodeArmTicketUpdate)
          .toList(growable: false),
      'attachments': value.attachments
          .map(encodeArmTicketAttachment)
          .toList(growable: false),
      if (value.statusUpdatedBy != null)
        'statusUpdatedBy': value.statusUpdatedBy,
      if (value.statusUpdatedAt != null)
        'statusUpdatedAt': _utc(value.statusUpdatedAt!).toIso8601String(),
    };

ArmTicketRecord decodeArmTicketRecord(Object? value, String path) {
  final json = _object(value, path);
  _keys(
    json,
    required: const <String>{
      'ticketId',
      'title',
      'description',
      'status',
      'createdAt',
      'updatedAt',
      'createdBy',
    },
    optional: const <String>{
      'reporterContact',
      'caseIds',
      'issueId',
      'sessionId',
      'allowlist',
      'updates',
      'attachments',
      'statusUpdatedBy',
      'statusUpdatedAt',
    },
    path: path,
  );
  final updates = _list(json['updates'] ?? const <Object?>[], '$path.updates');
  if (updates.length > armMaximumTicketUpdates) {
    throw FormatException(
      '$path.updates may hold at most $armMaximumTicketUpdates entries.',
    );
  }
  final caseIds = _resourceIdList(json['caseIds'], '$path.caseIds');
  if (caseIds.length > armMaximumTicketCases) {
    throw FormatException(
      '$path.caseIds may name at most $armMaximumTicketCases case logs.',
    );
  }
  return ArmTicketRecord(
    ticketId: _resourceId(json['ticketId'], '$path.ticketId'),
    title: _boundedText(json['title'], '$path.title', 200),
    description: _boundedText(
      json['description'],
      '$path.description',
      armMaximumTicketUpdateBody,
    ),
    status: _enumOf(ArmTicketStatus.values, json['status'], '$path.status'),
    createdAt: _dateTime(json['createdAt'], '$path.createdAt'),
    updatedAt: _dateTime(json['updatedAt'], '$path.updatedAt'),
    createdBy: _boundedText(json['createdBy'], '$path.createdBy', 320),
    reporterContact: json['reporterContact'] == null
        ? null
        : _boundedText(json['reporterContact'], '$path.reporterContact', 320),
    caseIds: caseIds,
    issueId: _optionalResourceId(json['issueId'], '$path.issueId'),
    sessionId: _optionalResourceId(json['sessionId'], '$path.sessionId'),
    allowlist: armNormalizedAllowlist(json['allowlist'], '$path.allowlist'),
    updates: <ArmTicketUpdate>[
      for (int index = 0; index < updates.length; index += 1)
        decodeArmTicketUpdate(updates[index], '$path.updates[$index]'),
    ],
    attachments: _ticketAttachments(json['attachments'], '$path.attachments'),
    statusUpdatedBy: _optionalString(
      json['statusUpdatedBy'],
      '$path.statusUpdatedBy',
    ),
    statusUpdatedAt: json['statusUpdatedAt'] == null
        ? null
        : _dateTime(json['statusUpdatedAt'], '$path.statusUpdatedAt'),
  );
}

Map<String, Object?> encodeArmTicketPage(ArmTicketPage value) =>
    <String, Object?>{
      'projectId': value.projectId,
      'tickets': value.tickets
          .map(encodeArmTicketRecord)
          .toList(growable: false),
      if (value.nextPageToken != null) 'nextPageToken': value.nextPageToken,
    };

ArmTicketPage decodeArmTicketPage(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'projectId'},
    optional: const <String>{'tickets', 'nextPageToken', 'requestId'},
    path: r'$',
  );
  final tickets = _list(json['tickets'] ?? const <Object?>[], r'$.tickets');
  return ArmTicketPage(
    projectId: _resourceId(json['projectId'], r'$.projectId'),
    tickets: <ArmTicketRecord>[
      for (int index = 0; index < tickets.length; index += 1)
        decodeArmTicketRecord(tickets[index], '\$.tickets[$index]'),
    ],
    nextPageToken: _optionalString(json['nextPageToken'], r'$.nextPageToken'),
  );
}

ArmTicketDraft decodeArmTicketDraft(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'title', 'description'},
    optional: const <String>{
      'reporterContact',
      'caseIds',
      'issueId',
      'sessionId',
      'allowlist',
      'attachments',
    },
    path: r'$',
  );
  final caseIds = _resourceIdList(json['caseIds'], r'$.caseIds');
  if (caseIds.length > armMaximumTicketCases) {
    throw FormatException(
      '\$.caseIds may name at most $armMaximumTicketCases case logs.',
    );
  }
  return ArmTicketDraft(
    title: _boundedText(json['title'], r'$.title', 200),
    description: _boundedText(
      json['description'],
      r'$.description',
      armMaximumTicketUpdateBody,
    ),
    reporterContact: json['reporterContact'] == null
        ? null
        : _boundedText(json['reporterContact'], r'$.reporterContact', 320),
    caseIds: caseIds,
    issueId: _optionalResourceId(json['issueId'], r'$.issueId'),
    sessionId: _optionalResourceId(json['sessionId'], r'$.sessionId'),
    allowlist: armNormalizedAllowlist(json['allowlist'], r'$.allowlist'),
    attachments: _ticketAttachments(json['attachments'], r'$.attachments'),
  );
}

ArmTicketUpdateDraft decodeArmTicketUpdateDraft(Object? value) {
  final json = _object(value, r'$');
  _keys(
    json,
    required: const <String>{'body'},
    optional: const <String>{'authorKind', 'attachments'},
    path: r'$',
  );
  return ArmTicketUpdateDraft(
    // Defaults to the operator, because this route is reached through the
    // Platform API with an authenticated operator behind it. A customer's
    // entry is written by the public route, which names the kind itself.
    authorKind: _enumOf(
      ArmTicketAuthorKind.values,
      json['authorKind'] ?? ArmTicketAuthorKind.operator.name,
      r'$.authorKind',
    ),
    body: _boundedText(json['body'], r'$.body', armMaximumTicketUpdateBody),
    attachments: _ticketAttachments(json['attachments'], r'$.attachments'),
  );
}

ArmTicketStatusPatch decodeArmTicketStatusPatch(Object? value) {
  final json = _object(value, r'$');
  _keys(json, required: const <String>{'status'}, path: r'$');
  return ArmTicketStatusPatch(
    status: _enumOf(ArmTicketStatus.values, json['status'], r'$.status'),
  );
}

ArmTicketAccessPatch decodeArmTicketAccessPatch(Object? value) {
  final json = _object(value, r'$');
  _keys(json, required: const <String>{'allowlist'}, path: r'$');
  return ArmTicketAccessPatch(
    allowlist: armNormalizedAllowlist(json['allowlist'], r'$.allowlist'),
  );
}
