# ARM Tooling Server Notes

## Scope
This package is the server/runtime ARM SDK layer. It adds request-aware
capture, service-account Firestore persistence, and server exception
normalization on top of `arm_tooling_core`.

## Constraints
- Keep `errorType`, `errorName`, and `message` raw. Do not wrap them with
  custom labels; put app-specific classification in `feature`, `operation`,
  `category`, `tags`, or request context.
- `errorData` must contain sanitized structured details only.
- Request context helpers should capture trustworthy request/session metadata
  and keep SDK-owned `sessionId` context authoritative.

## Directory guide
- `lib/src/arm_server.dart`: main server capture API and guarded execution.
- `lib/src/arm_http_middleware.dart`: request-scoped wrapper helpers.
- `lib/src/arm_request_context.dart`: HTTP request/session context builders.
- `lib/src/arm_server_error.dart`: server exception normalization.
- `lib/src/arm_firestore_service_account_sink.dart`: Firestore API sink using
  service-account auth.
- `lib/src/arm_response.dart`: case-ID response/header helpers.
