import 'dart:convert';

import 'package:http/http.dart' as http;

import 'arm_private_service.dart';
import 'arm_service_models.dart';

const int _maximumTokenBytes = 16 * 1024;
const int _maximumTokenInfoBytes = 8 * 1024;

final Uri _googleTokenInfoEndpoint = Uri.parse(
  'https://oauth2.googleapis.com/tokeninfo',
);

/// Authorizes the private ARM service to exactly the Platform API runtime
/// identities that Cloud Run IAM already admits, then carries the operator the
/// caller authenticated into the evidence mutation.
///
/// Google signs and validates the caller's OIDC identity token, so the token is
/// checked against Google's own `tokeninfo` endpoint rather than reimplementing
/// JWT verification here. Successful results are cached until the token
/// expires, which keeps the check to roughly one call per caller per hour.
ArmPrivateRequestAuthorizer createGoogleOidcArmAuthorizer({
  required String expectedAudience,
  required Set<String> allowedCallerEmails,
  http.Client? httpClient,
  DateTime Function()? clock,
}) {
  if (expectedAudience.trim() != expectedAudience || expectedAudience.isEmpty) {
    throw ArgumentError('The expected audience must be non-empty and trimmed.');
  }
  final normalizedCallers = allowedCallerEmails
      .map((email) => email.trim().toLowerCase())
      .where((email) => email.isNotEmpty)
      .toSet();
  if (normalizedCallers.isEmpty) {
    throw ArgumentError('At least one allowed caller email is required.');
  }

  final client = httpClient ?? http.Client();
  final now = clock ?? (() => DateTime.now().toUtc());
  final verifiedTokens = <String, _VerifiedCaller>{};

  return (ArmAuthorizationRequest request) async {
    final token = _bearerToken(request.authorizationHeader);
    if (token == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.unauthenticated,
        message: 'A Google identity token is required.',
      );
    }

    final currentTime = now();
    verifiedTokens.removeWhere(
      (_, caller) => !caller.expiresAt.isAfter(currentTime),
    );
    final cached = verifiedTokens[token];
    if (cached == null) {
      final caller = await _verifyCaller(
        client: client,
        token: token,
        expectedAudience: expectedAudience,
        allowedCallerEmails: normalizedCallers,
        currentTime: currentTime,
      );
      verifiedTokens[token] = caller;
    }

    return _principal(request);
  };
}

Future<_VerifiedCaller> _verifyCaller({
  required http.Client client,
  required String token,
  required String expectedAudience,
  required Set<String> allowedCallerEmails,
  required DateTime currentTime,
}) async {
  final http.Response response;
  try {
    response = await client.get(
      _googleTokenInfoEndpoint.replace(
        queryParameters: <String, String>{'id_token': token},
      ),
    );
  } on Object {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.unavailable,
      message: 'Caller identity verification is unavailable.',
      retryable: true,
    );
  }

  if (response.statusCode >= 500) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.unavailable,
      message: 'Caller identity verification is unavailable.',
      retryable: true,
    );
  }
  if (response.statusCode != 200 ||
      response.bodyBytes.length > _maximumTokenInfoBytes) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.permissionDenied,
      message: 'The caller identity token was rejected.',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(response.bodyBytes));
  } on Object {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.permissionDenied,
      message: 'The caller identity token was rejected.',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.permissionDenied,
      message: 'The caller identity token was rejected.',
    );
  }

  final email = (decoded['email'] as String?)?.trim().toLowerCase();
  final audience = decoded['aud'] as String?;
  final issuer = decoded['iss'] as String?;
  final expiry = _epochSeconds(decoded['exp']);
  final emailVerified =
      decoded['email_verified'] == true || decoded['email_verified'] == 'true';

  if (audience != expectedAudience ||
      issuer != 'https://accounts.google.com' ||
      email == null ||
      !emailVerified ||
      !allowedCallerEmails.contains(email) ||
      expiry == null ||
      !expiry.isAfter(currentTime)) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.permissionDenied,
      message: 'The caller is not an authorized ARM evidence client.',
    );
  }

  return _VerifiedCaller(email: email, expiresAt: expiry);
}

ArmAuthorizedPrincipal _principal(ArmAuthorizationRequest request) {
  final actorId = request.forwardedActorId?.trim();
  final actorEmail = request.forwardedActorEmail?.trim().toLowerCase();
  final needsOperator =
      request.operation == ArmPrivateOperation.updateIssueStatus ||
      request.operation == ArmPrivateOperation.updateCaseStatus;

  if (needsOperator &&
      (actorId == null ||
          actorId.isEmpty ||
          actorEmail == null ||
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(actorEmail))) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.permissionDenied,
      message: 'The caller did not forward a complete operator identity.',
    );
  }

  return ArmAuthorizedPrincipal(
    actorId: actorId == null || actorId.isEmpty
        ? 'citadel_platform_api'
        : actorId,
    actorEmail: actorEmail == null || actorEmail.isEmpty ? null : actorEmail,
  );
}

String? _bearerToken(String header) {
  if (!header.startsWith('Bearer ')) return null;
  final token = header.substring('Bearer '.length).trim();
  if (token.isEmpty || utf8.encode(token).length > _maximumTokenBytes) {
    return null;
  }
  return token;
}

DateTime? _epochSeconds(Object? value) {
  final seconds = value is String
      ? int.tryParse(value)
      : (value is int ? value : null);
  if (seconds == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

class _VerifiedCaller {
  const _VerifiedCaller({required this.email, required this.expiresAt});

  final String email;
  final DateTime expiresAt;
}
