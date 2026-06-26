# Citadel ARM Tooling Notes

## Scope
This package is the reusable ARM client-side monitoring SDK for Flutter apps.
Shared pure-Dart ARM primitives now live in `../tooling_core`, while
server/runtime capture lives in `../tooling_server`.

## Constraints
- Keep the package generic and embeddable; project-specific routing, roles, labels, and recovery policies belong in host apps.
- Keep storage writes optional. Firestore-only mode must continue to work when Firebase Storage is absent.
- Preserve low runtime overhead. Avoid polling, streams, or heavyweight background work unless a feature explicitly requires it.
- Prefer additive schema changes. Existing issue and case documents must remain readable after upgrades.
- Do not add Firebase rules here. Rules belong to the consuming app or monitored project setup docs.
- ARM error capture must persist the raw runtime error name and payload text. Keep `errorType` mapped to `error.runtimeType.toString()` and `message` mapped to `error.toString()`; do not wrap either value with custom labels or app-specific prefixes.
- Preserve ARM session context capture. When the host app provides UID, email, or route providers, those values must be written into the captured `context` payload and kept authoritative over overlapping `contextBuilder()` keys.

## Directory guide
- `lib/src/arm_client.dart`: public capture and tracked-operation API.
- `lib/src/arm_bootstrap.dart`: Flutter, dispatcher, and zone wiring.
- `lib/src/arm_firebase_sink.dart`: Firestore and Firebase Storage persistence.
- `lib/src/arm_capture_boundary.dart`: optional screenshot capture helper.
- `../tooling_core/lib/src/arm_fingerprint.dart`: deterministic dedupe logic.
- `../tooling_core/lib/src/arm_types.dart`: shared severity and breadcrumb
  contracts.
- `../tooling_core/lib/src/arm_sink.dart`: shared capture request/result
  contracts.
