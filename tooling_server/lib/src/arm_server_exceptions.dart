class ServerRequestFailedException implements Exception {
  ServerRequestFailedException({
    required this.message,
    this.statusCode,
    this.responseContent,
  });

  final String message;
  final int? statusCode;
  final Object? responseContent;

  @override
  String toString() => '$runtimeType: $message';
}

class AccessDeniedException implements Exception {
  AccessDeniedException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}
