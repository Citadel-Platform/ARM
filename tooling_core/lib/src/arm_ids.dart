import 'dart:convert';

import 'package:crypto/crypto.dart';

String buildArmIssueId(String fingerprint) {
  final digest = sha256.convert(utf8.encode(fingerprint)).toString();
  return 'issue_${digest.substring(0, 24)}';
}

String buildArmCaseId() {
  final now = DateTime.now().toUtc();
  final date = [
    now.year.toString().padLeft(4, '0'),
    now.month.toString().padLeft(2, '0'),
    now.day.toString().padLeft(2, '0'),
  ].join();
  final seed = '${now.microsecondsSinceEpoch}-${now.hashCode}';
  final suffix = sha1
      .convert(utf8.encode(seed))
      .toString()
      .substring(0, 8)
      .toUpperCase();
  return 'ARM-$date-$suffix';
}

String buildArmSessionId(String seed, {String prefix = 'session'}) {
  final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final hash = Object.hash(seed, timestamp).toUnsigned(32).toRadixString(16);
  return '$prefix-$timestamp-$hash';
}
