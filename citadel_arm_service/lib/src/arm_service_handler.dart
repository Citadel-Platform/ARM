import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'arm_private_service.dart';
import 'arm_service_json.dart';
import 'arm_service_models.dart';

const int _maximumCommandBodyBytes = 4096;

/// Headers a verified Platform API caller uses to forward the human operator it
/// already authenticated and authorized.
const String armForwardedActorIdHeader = 'x-citadel-actor-id';
const String armForwardedActorEmailHeader = 'x-citadel-actor-email';

Handler createArmPrivateServiceHandler({
  required ArmPrivateService service,
  required ArmPrivateRequestAuthorizer authorizer,
}) {
  return (Request request) async {
    final requestId = _requestId(request.headers['x-request-id']);
    try {
      final route = _route(request);
      final principal = await _authorize(
        request: request,
        requestId: requestId,
        route: route,
        authorizer: authorizer,
      );

      switch (route.operation) {
        case ArmPrivateOperation.listIssues:
          final query = _issueQuery(request.url.queryParametersAll);
          final page = await service.listIssues(
            projectId: route.projectId,
            query: query,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmIssuePage(page),
          });
        case ArmPrivateOperation.listCases:
          final query = _caseQuery(request.url.queryParametersAll);
          final page = await service.listCases(
            projectId: route.projectId,
            query: query,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmCasePage(page),
          });
        case ArmPrivateOperation.getCaseDetail:
          final detail = await service.getCaseDetail(
            projectId: route.projectId,
            caseId: route.resourceId!,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmCaseDetail(detail),
          });
        case ArmPrivateOperation.updateIssueStatus:
          final patch = decodeArmIssueStatusPatch(await _jsonBody(request));
          final issue = await service.updateIssueStatus(
            projectId: route.projectId,
            issueId: route.resourceId!,
            status: patch.status,
            principal: principal,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'issue': encodeArmIssueRecord(issue),
          });
        case ArmPrivateOperation.listTickets:
          final query = _ticketQuery(request.url.queryParametersAll);
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmTicketPage(
              await service.listTickets(
                projectId: route.projectId,
                query: query,
              ),
            ),
          });
        case ArmPrivateOperation.getTicket:
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'ticket': encodeArmTicketRecord(
              await service.getTicket(
                projectId: route.projectId,
                ticketId: route.resourceId!,
              ),
            ),
          });
        case ArmPrivateOperation.createTicket:
          final draft = decodeArmTicketDraft(await _jsonBody(request));
          return _jsonResponse(201, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'ticket': encodeArmTicketRecord(
              await service.createTicket(
                projectId: route.projectId,
                draft: draft,
                openedBy: principal.actorEmail ?? principal.actorId,
              ),
            ),
          });
        case ArmPrivateOperation.updateTicketStatus:
          final patch = decodeArmTicketStatusPatch(await _jsonBody(request));
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'ticket': encodeArmTicketRecord(
              await service.updateTicketStatus(
                projectId: route.projectId,
                ticketId: route.resourceId!,
                status: patch.status,
                principal: principal,
              ),
            ),
          });
        case ArmPrivateOperation.appendTicketUpdate:
          final draft = decodeArmTicketUpdateDraft(await _jsonBody(request));
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'ticket': encodeArmTicketRecord(
              await service.appendTicketUpdate(
                projectId: route.projectId,
                ticketId: route.resourceId!,
                draft: draft,
                // Named here, never from the body. An author label a caller
                // chose is a message anybody can sign as somebody else — so a
                // customer's entry is attributed to the constant `Customer`,
                // and an operator's to the identity the Platform API
                // authenticated and forwarded.
                authorLabel:
                    draft.authorKind == ArmTicketAuthorKind.endUser
                    ? 'Customer'
                    : (principal.actorEmail ?? principal.actorId),
              ),
            ),
          });
        case ArmPrivateOperation.updateTicketAccess:
          final patch = decodeArmTicketAccessPatch(await _jsonBody(request));
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'ticket': encodeArmTicketRecord(
              await service.updateTicketAccess(
                projectId: route.projectId,
                ticketId: route.resourceId!,
                allowlist: patch.allowlist,
                principal: principal,
              ),
            ),
          });
        case ArmPrivateOperation.readAlerting:
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmAlertingConfiguration(
              await service.readAlerting(projectId: route.projectId),
            ),
          });
        case ArmPrivateOperation.writePolicy:
          final policy = decodeArmPolicyRecord(await _jsonBody(request), r'$');
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmAlertingConfiguration(
              await service.writePolicy(
                projectId: route.projectId,
                policy: policy,
                principal: principal,
              ),
            ),
          });
        case ArmPrivateOperation.deletePolicy:
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmAlertingConfiguration(
              await service.deletePolicy(
                projectId: route.projectId,
                policyId: route.resourceId!,
                principal: principal,
              ),
            ),
          });
        case ArmPrivateOperation.writeChannel:
          final channel = decodeArmNotificationChannel(
            await _jsonBody(request),
            r'$',
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmAlertingConfiguration(
              await service.writeChannel(
                projectId: route.projectId,
                channel: channel,
                principal: principal,
              ),
            ),
          });
        case ArmPrivateOperation.deleteChannel:
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            ...encodeArmAlertingConfiguration(
              await service.deleteChannel(
                projectId: route.projectId,
                channelId: route.resourceId!,
                principal: principal,
              ),
            ),
          });
        case ArmPrivateOperation.testChannel:
          final outcome = await service.testChannel(
            projectId: route.projectId,
            channelId: route.resourceId!,
            principal: principal,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            ...encodeArmChannelTestOutcome(outcome),
          });
        case ArmPrivateOperation.updateCaseSeverity:
          final patch = decodeArmCaseSeverityPatch(await _jsonBody(request));
          final caseRecord = await service.updateCaseSeverity(
            projectId: route.projectId,
            caseId: route.resourceId!,
            severity: patch.severity,
            principal: principal,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'case': encodeArmCaseRecord(caseRecord),
          });
        case ArmPrivateOperation.updateIssueTags:
          final patch = decodeArmIssueTagsPatch(await _jsonBody(request));
          final issue = await service.updateIssueTags(
            projectId: route.projectId,
            issueId: route.resourceId!,
            tags: patch.tags,
            principal: principal,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'issue': encodeArmIssueRecord(issue),
          });
        case ArmPrivateOperation.updateCaseStatus:
          final patch = decodeArmCaseStatusPatch(await _jsonBody(request));
          final caseRecord = await service.updateCaseStatus(
            projectId: route.projectId,
            caseId: route.resourceId!,
            status: patch.status,
            principal: principal,
          );
          return _jsonResponse(200, <String, Object?>{
            'requestId': requestId,
            'projectId': route.projectId,
            'case': encodeArmCaseRecord(caseRecord),
          });
      }
    } on ArmServiceException catch (error) {
      return _errorResponse(requestId, error);
    } on FormatException {
      return _errorResponse(
        requestId,
        const ArmServiceException(
          code: ArmServiceErrorCode.invalidArgument,
          message: 'Request body or query is invalid.',
        ),
      );
    } catch (_) {
      return _errorResponse(
        requestId,
        const ArmServiceException(
          code: ArmServiceErrorCode.internal,
          message: 'ARM service request failed.',
        ),
      );
    }
  };
}

Future<ArmAuthorizedPrincipal> _authorize({
  required Request request,
  required String requestId,
  required _ArmRoute route,
  required ArmPrivateRequestAuthorizer authorizer,
}) async {
  final authorization = request.headers['authorization']?.trim();
  if (authorization == null || authorization.isEmpty) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.unauthenticated,
      message: 'Private service authorization is required.',
    );
  }
  try {
    final principal = await authorizer(
      ArmAuthorizationRequest(
        requestId: requestId,
        operation: route.operation,
        projectId: route.projectId,
        authorizationHeader: authorization,
        forwardedActorId: request.headers[armForwardedActorIdHeader]?.trim(),
        forwardedActorEmail: request.headers[armForwardedActorEmailHeader]
            ?.trim(),
      ),
    );
    if (principal == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.permissionDenied,
        message: 'Private service authorization was denied.',
      );
    }
    return principal;
  } on ArmServiceException {
    rethrow;
  } catch (_) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.unavailable,
      message: 'Private service authorization is unavailable.',
      retryable: true,
    );
  }
}

_ArmRoute _route(Request request) {
  final segments = request.url.pathSegments;
  if (segments.length < 5 ||
      segments[0] != 'v1' ||
      segments[1] != 'projects' ||
      segments[3] != 'arm') {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.notFound,
      message: 'ARM service route was not found.',
    );
  }
  final projectId = _resourceId(segments[2], 'projectId');
  final resource = segments[4];
  if (request.method == 'GET' && segments.length == 5 && resource == 'issues') {
    return _ArmRoute(
      operation: ArmPrivateOperation.listIssues,
      projectId: projectId,
    );
  }
  if (request.method == 'GET' && segments.length == 5 && resource == 'cases') {
    return _ArmRoute(
      operation: ArmPrivateOperation.listCases,
      projectId: projectId,
    );
  }
  if (request.method == 'GET' && segments.length == 6 && resource == 'cases') {
    return _ArmRoute(
      operation: ArmPrivateOperation.getCaseDetail,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'caseId'),
    );
  }
  if (request.method == 'PATCH' &&
      segments.length == 7 &&
      segments[6] == 'status' &&
      resource == 'issues') {
    return _ArmRoute(
      operation: ArmPrivateOperation.updateIssueStatus,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'issueId'),
    );
  }
  if (request.method == 'PATCH' &&
      segments.length == 7 &&
      segments[6] == 'status' &&
      resource == 'cases') {
    return _ArmRoute(
      operation: ArmPrivateOperation.updateCaseStatus,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'caseId'),
    );
  }
  if (request.method == 'GET' &&
      segments.length == 5 &&
      resource == 'alerting') {
    return _ArmRoute(
      operation: ArmPrivateOperation.readAlerting,
      projectId: projectId,
    );
  }
  if (request.method == 'PUT' &&
      segments.length == 7 &&
      resource == 'alerting' &&
      segments[5] == 'policies') {
    return _ArmRoute(
      operation: ArmPrivateOperation.writePolicy,
      projectId: projectId,
    );
  }
  if (request.method == 'DELETE' &&
      segments.length == 7 &&
      resource == 'alerting' &&
      segments[5] == 'policies') {
    return _ArmRoute(
      operation: ArmPrivateOperation.deletePolicy,
      projectId: projectId,
      resourceId: _resourceId(segments[6], 'policyId'),
    );
  }
  if (request.method == 'PUT' &&
      segments.length == 7 &&
      resource == 'alerting' &&
      segments[5] == 'channels') {
    return _ArmRoute(
      operation: ArmPrivateOperation.writeChannel,
      projectId: projectId,
    );
  }
  if (request.method == 'DELETE' &&
      segments.length == 7 &&
      resource == 'alerting' &&
      segments[5] == 'channels') {
    return _ArmRoute(
      operation: ArmPrivateOperation.deleteChannel,
      projectId: projectId,
      resourceId: _resourceId(segments[6], 'channelId'),
    );
  }
  if (request.method == 'POST' &&
      segments.length == 8 &&
      resource == 'alerting' &&
      segments[5] == 'channels' &&
      segments[7] == 'test') {
    return _ArmRoute(
      operation: ArmPrivateOperation.testChannel,
      projectId: projectId,
      resourceId: _resourceId(segments[6], 'channelId'),
    );
  }
  if (request.method == 'PATCH' &&
      segments.length == 7 &&
      segments[6] == 'severity' &&
      resource == 'cases') {
    return _ArmRoute(
      operation: ArmPrivateOperation.updateCaseSeverity,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'caseId'),
    );
  }
  if (request.method == 'PATCH' &&
      segments.length == 7 &&
      segments[6] == 'tags' &&
      resource == 'issues') {
    return _ArmRoute(
      operation: ArmPrivateOperation.updateIssueTags,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'issueId'),
    );
  }
  if (segments.length == 5 && resource == 'tickets') {
    if (request.method == 'GET') {
      return _ArmRoute(
        operation: ArmPrivateOperation.listTickets,
        projectId: projectId,
      );
    }
    if (request.method == 'POST') {
      return _ArmRoute(
        operation: ArmPrivateOperation.createTicket,
        projectId: projectId,
      );
    }
  }
  if (request.method == 'GET' &&
      segments.length == 6 &&
      resource == 'tickets') {
    return _ArmRoute(
      operation: ArmPrivateOperation.getTicket,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'ticketId'),
    );
  }
  if (request.method == 'PATCH' &&
      segments.length == 7 &&
      resource == 'tickets' &&
      segments[6] == 'status') {
    return _ArmRoute(
      operation: ArmPrivateOperation.updateTicketStatus,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'ticketId'),
    );
  }
  if (request.method == 'POST' &&
      segments.length == 7 &&
      resource == 'tickets' &&
      segments[6] == 'updates') {
    return _ArmRoute(
      operation: ArmPrivateOperation.appendTicketUpdate,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'ticketId'),
    );
  }
  if (request.method == 'PATCH' &&
      segments.length == 7 &&
      resource == 'tickets' &&
      segments[6] == 'access') {
    return _ArmRoute(
      operation: ArmPrivateOperation.updateTicketAccess,
      projectId: projectId,
      resourceId: _resourceId(segments[5], 'ticketId'),
    );
  }
  throw const ArmServiceException(
    code: ArmServiceErrorCode.notFound,
    message: 'ARM service route was not found.',
  );
}

ArmIssueQuery _issueQuery(Map<String, List<String>> parameters) {
  _queryKeys(parameters, const <String>{'since', 'pageSize', 'pageToken'});
  return ArmIssueQuery(
    since: _since(parameters),
    pageSize: _pageSize(parameters),
    cursor: _pageCursor(parameters),
  );
}

ArmCaseQuery _caseQuery(Map<String, List<String>> parameters) {
  _queryKeys(parameters, const <String>{
    'since',
    'issueId',
    'pageSize',
    'pageToken',
  });
  final issueId = _single(parameters, 'issueId');
  return ArmCaseQuery(
    since: _since(parameters),
    issueId: issueId == null ? null : _resourceId(issueId, 'issueId'),
    pageSize: _pageSize(parameters),
    cursor: _pageCursor(parameters),
  );
}

ArmTicketQuery _ticketQuery(Map<String, List<String>> parameters) {
  _queryKeys(parameters, const <String>{
    'status',
    'issueId',
    'pageSize',
    'pageToken',
  });
  final String? status = _single(parameters, 'status');
  final String? issueId = _single(parameters, 'issueId');
  return ArmTicketQuery(
    status: status == null ? null : _ticketStatus(status),
    issueId: issueId == null ? null : _resourceId(issueId, 'issueId'),
    pageSize: _pageSize(parameters),
    cursor: _pageCursor(parameters),
  );
}

ArmTicketStatus _ticketStatus(String value) {
  for (final ArmTicketStatus status in ArmTicketStatus.values) {
    if (status.name == value) return status;
  }
  throw const ArmServiceException(
    code: ArmServiceErrorCode.invalidArgument,
    message: 'Query parameter status is invalid.',
  );
}

void _queryKeys(Map<String, List<String>> parameters, Set<String> allowed) {
  for (final entry in parameters.entries) {
    if (!allowed.contains(entry.key) || entry.value.length != 1) {
      throw ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: 'Query parameter ${entry.key} is invalid.',
      );
    }
  }
}

DateTime? _since(Map<String, List<String>> parameters) {
  final value = _single(parameters, 'since');
  if (value == null) {
    return null;
  }
  try {
    return parseArmUtcTimestamp(value, fieldName: 'since');
  } on FormatException {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: 'since must be an ISO-8601 UTC timestamp.',
    );
  }
}

int _pageSize(Map<String, List<String>> parameters) {
  final value = _single(parameters, 'pageSize');
  if (value == null) {
    return armDefaultPageSize;
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed.toString() != value) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: 'pageSize must be an integer between 1 and 100.',
    );
  }
  return parsed;
}

ArmPageCursor? _pageCursor(Map<String, List<String>> parameters) {
  final value = _single(parameters, 'pageToken');
  if (value == null) {
    return null;
  }
  try {
    return decodeArmPageToken(value);
  } on FormatException {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: 'pageToken is invalid.',
    );
  }
}

String? _single(Map<String, List<String>> parameters, String key) {
  final values = parameters[key];
  return values?.single;
}

String _resourceId(String value, String field) {
  try {
    return validateArmResourceId(value, fieldName: field);
  } on FormatException {
    throw ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: '$field is invalid.',
    );
  }
}

Future<Object?> _jsonBody(Request request) async {
  final contentType = request.headers['content-type']?.split(';').first.trim();
  if (contentType != 'application/json') {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: 'Content-Type must be application/json.',
    );
  }
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in request.read()) {
    length += chunk.length;
    if (length > _maximumCommandBodyBytes) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: 'Request body is too large.',
      );
    }
    builder.add(chunk);
  }
  if (length == 0) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: 'Request body is required.',
    );
  }
  try {
    return jsonDecode(utf8.decode(builder.takeBytes(), allowMalformed: false));
  } catch (_) {
    throw const ArmServiceException(
      code: ArmServiceErrorCode.invalidArgument,
      message: 'Request body must be valid UTF-8 JSON.',
    );
  }
}

Response _errorResponse(String requestId, ArmServiceException exception) {
  final error = ArmServiceError(
    code: exception.code,
    message: exception.message,
    requestId: requestId,
    retryable: exception.retryable,
    details: exception.details,
  );
  return _jsonResponse(_statusCode(exception.code), <String, Object?>{
    'error': encodeArmServiceError(error),
  });
}

int _statusCode(ArmServiceErrorCode code) => switch (code) {
  ArmServiceErrorCode.invalidArgument => 400,
  ArmServiceErrorCode.unauthenticated => 401,
  ArmServiceErrorCode.permissionDenied => 403,
  ArmServiceErrorCode.notFound => 404,
  ArmServiceErrorCode.failedPrecondition => 412,
  ArmServiceErrorCode.unavailable => 503,
  ArmServiceErrorCode.internal => 500,
};

Response _jsonResponse(int statusCode, Map<String, Object?> body) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  );
}

String _requestId(String? candidate) {
  final value = candidate?.trim();
  if (value != null &&
      value == candidate &&
      RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    return value;
  }
  final random = Random.secure();
  final suffix = List<int>.generate(
    12,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return 'arm_$suffix';
}

final class _ArmRoute {
  const _ArmRoute({
    required this.operation,
    required this.projectId,
    this.resourceId,
  });

  final ArmPrivateOperation operation;
  final String projectId;
  final String? resourceId;
}
