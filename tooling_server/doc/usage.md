# Usage Guide

Create one shared `ArmServer` for your process and point it at the service-
account Firestore sink:

```dart
final sink = await FirestoreServiceAccountArmSink.fromServiceAccountJson(
  serviceAccount: serviceAccountJson,
);

final armServer = ArmServer(
  sink: sink,
  appId: 'citadel-api',
  environment: 'production',
  contextBuilder: () => <String, dynamic>{
    'region': 'us-central1',
    'service': 'oauth-api',
  },
);
```

Wrap startup:

```dart
await ArmServer.runGuarded(
  server: armServer,
  body: () async {
    await serveRequests();
  },
);
```

Wrap HTTP handlers when you need request-scoped capture:

```dart
await ArmHttpMiddleware.wrap<void>(
  server: armServer,
  request: request,
  feature: 'oauth',
  operation: 'callback',
  userId: resolvedUserId,
  userEmail: resolvedUserEmail,
  requestId: request.headers.value('x-request-id'),
  traceId: request.headers.value('x-cloud-trace-context'),
  action: () async {
    await handleOauthCallback(request);
  },
);
```

When the server reports an ARM case, `respondArmJson(...)` and
`applyArmCaseIdHeader(...)` expose the case ID only when the recorded severity
allows it.

Server captures preserve the raw normalized error identity:

- `errorType` / `errorName` are the raw normalized error name
- `message` is the raw error payload text
- structured details belong in `errorData`

Do not wrap those fields with custom labels. Put app-level classification in
`feature`, `operation`, `category`, `tags`, or request context.
