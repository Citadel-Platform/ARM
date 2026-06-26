# Server SDK Requirements

To replace `LAD_Server` feature-wise, the shared ARM SDK needs to be split into platform layers and gain a real server package.

## Recommended package split

### `arm_tooling_core`

Pure Dart only. Shared across Flutter and server runtimes.

Should contain:

- `ArmSeverity`
- capture request/result models
- fingerprinting
- case / issue ID generation
- sanitization helpers
- shared data contract for case documents

### `arm_tooling_flutter`

Flutter-specific integration.

Should contain:

- `ArmClient`
- `ArmBootstrap`
- `ArmCaptureBoundary`
- `FirebaseArmSink` for client Firestore / Storage access
- Flutter breadcrumb and `print()` capture

### `arm_tooling_server`

Server-specific integration.

Should contain:

- server ARM client / reporter
- startup guard
- request guard / middleware
- service-account Firestore sink
- request context helpers
- server exception normalization

## Minimum server features required to replace LAD_Server

### 1. Service-account Firestore sink

Equivalent to the current custom writer in:

- [LAD_Server/lad_server/lib/arm_monitoring.dart](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/LAD_Server/lad_server/lib/arm_monitoring.dart:20)

Requirements:

- Google service-account auth
- Firestore REST / API writes
- `armIssues` and `armCases` persistence
- stable issue and case ID generation

### 2. Server guard / middleware API

Equivalent to the current manual handling in:

- [LAD_Server/lad_server/lib/lad_server.dart](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/LAD_Server/lad_server/lib/lad_server.dart:24)

Recommended APIs:

- `ArmServer.runGuarded(...)`
- `ArmHttpMiddleware.wrap(...)`
- `ArmServer.captureException(...)`

### 3. Request context capture

Equivalent to:

- [buildRequestContext(...)](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/LAD_Server/lad_server/lib/arm_monitoring.dart:295)

Should support:

- HTTP method
- path
- query
- user-agent
- content type
- remote address
- optional user / auth context
- request ID / trace ID hooks

### 4. Structured server error normalization

Equivalent to:

- [describeArmError(...)](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/LAD_Server/lad_server/lib/arm_monitoring.dart:130)

The server SDK should normalize exceptions into:

- `errorName`
- `message`
- `errorData`

It should understand at least:

- `ServerRequestFailedException`
- `AccessDeniedException`
- `FileSystemException`
- `ProcessException`
- `SocketException`
- `HttpException`
- `FormatException`
- `ArgumentError`

### 5. Case-linking response helpers

To preserve current app/server integration, the server SDK should help emit:

- `x-arm-case-id`
- normalized error response payloads
- optional case-ID exposure rules by severity

That is required for the dashboard’s linked server-failure flow.

### 6. Server session / request correlation

Should support:

- server session IDs
- request IDs
- correlation IDs
- optional trace / span IDs

This should mirror the client session context model.

## Useful but not required for parity

- server breadcrumbs
- dependency-call breadcrumbs
- log adapters
- text or JSON attachments

These are worthwhile, but they are not required to replace the current `LAD_Server` implementation.

## Practical migration order

1. Extract shared fingerprinting and capture models into `arm_tooling_core`.
2. Move the current Flutter SDK to depend on `arm_tooling_core`.
3. Implement a service-account Firestore sink in `arm_tooling_server`.
4. Implement server context + exception normalization.
5. Add middleware helpers and case-ID response helpers.
6. Migrate `LAD_Server` from its custom reporter to the server SDK package.
