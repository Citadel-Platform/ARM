import 'dart:io';

import 'package:arm_tooling_core/arm_tooling_core.dart';

Map<String, dynamic> buildArmRequestContext(
  HttpRequest request, {
  String? userId,
  String? userEmail,
  String? authSubject,
  String? requestId,
  String? correlationId,
  String? traceId,
  String? spanId,
  Map<String, dynamic>? extra,
}) {
  final safeExtra = sanitizeArmMap(extra);
  final cleanedUserId = _cleanString(userId);
  final cleanedUserEmail = _cleanString(userEmail);
  final cleanedAuthSubject = _cleanString(authSubject);
  final cleanedRequestId = _cleanString(requestId);
  final cleanedCorrelationId = _cleanString(correlationId);
  final cleanedTraceId = _cleanString(traceId);
  final cleanedSpanId = _cleanString(spanId);

  final requestContext = <String, dynamic>{
    'method': request.method,
    'path': request.uri.path,
    if (request.uri.query.isNotEmpty) 'query': request.uri.query,
    if (request.headers.value(HttpHeaders.userAgentHeader) case final String ua
        when ua.trim().isNotEmpty)
      'userAgent': ua,
    if (request.headers.contentType case final ContentType contentType)
      'contentType': contentType.mimeType,
    if (request.connectionInfo?.remoteAddress.address case final String address
        when address.isNotEmpty)
      'remoteAddress': address,
    if (request.connectionInfo?.remotePort case final int remotePort)
      'remotePort': remotePort,
    if (cleanedRequestId != null) 'requestId': cleanedRequestId,
    if (cleanedCorrelationId != null) 'correlationId': cleanedCorrelationId,
    if (cleanedTraceId != null) 'traceId': cleanedTraceId,
    if (cleanedSpanId != null) 'spanId': cleanedSpanId,
  };

  return <String, dynamic>{
    if (safeExtra != null && safeExtra.isNotEmpty) ...safeExtra,
    if (cleanedUserId != null) 'userId': cleanedUserId,
    if (cleanedUserEmail != null) 'userEmail': cleanedUserEmail,
    if (cleanedAuthSubject != null) 'authSubject': cleanedAuthSubject,
    if (cleanedRequestId != null) 'requestId': cleanedRequestId,
    if (cleanedCorrelationId != null) 'correlationId': cleanedCorrelationId,
    if (cleanedTraceId != null) 'traceId': cleanedTraceId,
    if (cleanedSpanId != null) 'spanId': cleanedSpanId,
    'request': requestContext,
  };
}

String? _cleanString(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
