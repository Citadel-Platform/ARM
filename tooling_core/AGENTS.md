# ARM Tooling Core Notes

## Scope
This package owns the pure-Dart ARM primitives shared by Flutter and server
SDK layers.

## Constraints
- Keep this package runtime-agnostic. Do not add Flutter, Firebase, or server-
  framework dependencies here.
- Shared models and helpers must preserve the ARM storage contract across
  client and server writers.
- Sanitization and fingerprinting behavior must stay deterministic across
  runtimes.

## Directory guide
- `lib/src/arm_types.dart`: severity, breadcrumb, and callback contracts.
- `lib/src/arm_sink.dart`: capture request/result and sink interface.
- `lib/src/arm_fingerprint.dart`: deterministic dedupe logic.
- `lib/src/arm_ids.dart`: issue, case, and session ID generation.
- `lib/src/arm_sanitizer.dart`: shared payload sanitization helpers.
- `lib/src/arm_documents.dart`: shared issue/case document payload builders.
