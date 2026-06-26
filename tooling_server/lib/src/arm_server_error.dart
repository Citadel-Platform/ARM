import 'dart:convert';
import 'dart:io';

import 'package:arm_tooling_core/arm_tooling_core.dart';

import 'arm_server_exceptions.dart';

class ArmServerErrorDetails {
  const ArmServerErrorDetails({
    required this.name,
    required this.message,
    this.data = const <String, dynamic>{},
  });

  final String name;
  final String message;
  final Map<String, dynamic> data;
}

ArmServerErrorDetails describeArmServerError(Object error) {
  if (error is String) {
    return ArmServerErrorDetails(
      name: 'String',
      message: error,
      data: <String, dynamic>{'value': error},
    );
  }
  if (error is Map) {
    final data = sanitizeUntypedArmMap(error, depth: 0);
    return ArmServerErrorDetails(
      name:
          firstNonEmptyArmString(<Object?>[
            data['errorName'],
            data['name'],
            data['errorType'],
          ]) ??
          error.runtimeType.toString(),
      message:
          firstNonEmptyArmString(<Object?>[
            data['exception'],
            data['message'],
            data['error'],
          ]) ??
          jsonEncode(data),
      data: data,
    );
  }
  if (error is ServerRequestFailedException) {
    final responseContent = error.responseContent;
    final sanitizedResponse = switch (responseContent) {
      final Map value => sanitizeUntypedArmMap(value, depth: 0),
      final Iterable value => sanitizeArmValue(value, depth: 0),
      _ => responseContent?.toString(),
    };
    final oauthError = responseContent is Map
        ? responseContent['error']?.toString()
        : null;
    final oauthErrorDescription = responseContent is Map
        ? responseContent['error_description']?.toString()
        : null;
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.message,
      data: <String, dynamic>{
        'message': error.message,
        if (error.statusCode != null) 'statusCode': error.statusCode,
        if (oauthError != null) 'oauthError': oauthError,
        if (oauthErrorDescription != null)
          'oauthErrorDescription': oauthErrorDescription,
        if (sanitizedResponse != null) 'responseContent': sanitizedResponse,
      },
    );
  }
  if (error is AccessDeniedException) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.message,
      data: <String, dynamic>{'message': error.message},
    );
  }
  if (error is FileSystemException) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.toString(),
      data: <String, dynamic>{
        'message': error.message,
        if (error.path != null) 'path': error.path,
        if (error.osError != null)
          'osError': <String, dynamic>{
            'code': error.osError!.errorCode,
            'message': error.osError!.message,
          },
      },
    );
  }
  if (error is ProcessException) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.toString(),
      data: <String, dynamic>{
        'message': error.message,
        'executable': error.executable,
        if (error.arguments.isNotEmpty) 'arguments': error.arguments,
        'errorCode': error.errorCode,
      },
    );
  }
  if (error is SocketException) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.toString(),
      data: <String, dynamic>{
        'message': error.message,
        if (error.address != null) 'address': error.address.toString(),
        if (error.port != null) 'port': error.port,
        if (error.osError != null)
          'osError': <String, dynamic>{
            'code': error.osError!.errorCode,
            'message': error.osError!.message,
          },
      },
    );
  }
  if (error is HttpException) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.toString(),
      data: <String, dynamic>{
        'message': error.message,
        if (error.uri != null) 'uri': error.uri.toString(),
      },
    );
  }
  if (error is FormatException) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.toString(),
      data: <String, dynamic>{
        'formatMessage': error.message,
        if (error.source != null) 'source': error.source.toString(),
        if (error.offset != null) 'offset': error.offset,
      },
    );
  }
  if (error is ArgumentError) {
    return ArmServerErrorDetails(
      name: error.runtimeType.toString(),
      message: error.toString(),
      data: <String, dynamic>{
        if (error.message != null)
          'argumentErrorMessage': sanitizeArmValue(error.message, depth: 0),
        if (error.name != null) 'argumentName': error.name,
        if (error.invalidValue != null)
          'invalidValue': sanitizeArmValue(error.invalidValue, depth: 0),
      },
    );
  }
  return ArmServerErrorDetails(
    name: error.runtimeType.toString(),
    message: error.toString(),
    data: <String, dynamic>{'stringified': error.toString()},
  );
}
