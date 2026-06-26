Map<String, dynamic>? sanitizeArmMap(
  Map<String, dynamic>? value, {
  int maxDepth = 4,
  int maxEntries = 20,
  int maxStringLength = 2000,
}) {
  if (value == null) {
    return null;
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final safeValue = sanitizeArmValue(
      entry.value,
      depth: 0,
      maxDepth: maxDepth,
      maxEntries: maxEntries,
      maxStringLength: maxStringLength,
    );
    if (safeValue != null) {
      result[entry.key] = safeValue;
    }
  }
  return result;
}

Map<String, dynamic> sanitizeUntypedArmMap(
  Map value, {
  required int depth,
  int maxDepth = 4,
  int maxEntries = 20,
  int maxStringLength = 2000,
}) {
  final result = <String, dynamic>{};
  for (final entry in value.entries.take(maxEntries)) {
    result[entry.key.toString()] = sanitizeArmValue(
      entry.value,
      depth: depth + 1,
      maxDepth: maxDepth,
      maxEntries: maxEntries,
      maxStringLength: maxStringLength,
    );
  }
  return result;
}

dynamic sanitizeArmValue(
  dynamic value, {
  required int depth,
  int maxDepth = 4,
  int maxEntries = 20,
  int maxStringLength = 2000,
}) {
  if (depth > maxDepth) {
    return value?.toString();
  }
  if (value == null || value is num || value is bool) {
    return value;
  }
  if (value is String) {
    return value.length <= maxStringLength
        ? value
        : value.substring(0, maxStringLength);
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is Map) {
    return sanitizeUntypedArmMap(
      value,
      depth: depth,
      maxDepth: maxDepth,
      maxEntries: maxEntries,
      maxStringLength: maxStringLength,
    );
  }
  if (value is Iterable) {
    return value
        .take(maxEntries)
        .map(
          (item) => sanitizeArmValue(
            item,
            depth: depth + 1,
            maxDepth: maxDepth,
            maxEntries: maxEntries,
            maxStringLength: maxStringLength,
          ),
        )
        .toList(growable: false);
  }
  return value.toString();
}

String? firstNonEmptyArmString(Iterable<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }
  return null;
}
