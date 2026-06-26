import 'dart:convert';

String buildArmFingerprint({
  required String feature,
  required String operation,
  required String errorType,
  required String message,
  required StackTrace stackTrace,
}) {
  final normalizedMessage = _normalizeMessage(message);
  final frames = _normalizeFrames(stackTrace);
  return jsonEncode(<String, Object?>{
    'feature': feature.trim().toLowerCase(),
    'operation': operation.trim().toLowerCase(),
    'errorType': errorType.trim(),
    'message': normalizedMessage,
    'frames': frames,
  });
}

String _normalizeMessage(String value) {
  final squashed = value
      .replaceAll(RegExp(r'0x[0-9a-fA-F]+'), '<hex>')
      .replaceAll(RegExp(r'\b\d+\b'), '<n>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return squashed.length <= 240 ? squashed : squashed.substring(0, 240);
}

List<String> _normalizeFrames(StackTrace stackTrace) {
  return stackTrace
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map(
        (line) => line
            .replaceAll(RegExp(r'#[0-9]+\s+'), '')
            .replaceAll(RegExp(r':\d+:\d+'), '')
            .replaceAll(RegExp(r'<asynchronous suspension>'), '')
            .trim(),
      )
      .where((line) => line.isNotEmpty)
      .take(6)
      .toList(growable: false);
}
