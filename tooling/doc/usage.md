# Usage Guide

This guide covers the main runtime patterns for `arm_tooling` in
Citadel-managed and client-managed Flutter apps.

`arm_tooling` is the Flutter/client facet of the broader ARM SDK split.
Server-side capture now lives in `arm_tooling_server`, while shared pure-Dart
contracts live in `arm_tooling_core`.

## Create the client once

Create one shared `ArmClient` near app startup and inject it through your app's dependency system.

```dart
ArmClient createArmClient() {
  return ArmClient(
    sink: FirebaseArmSink(
      firestore: FirebaseFirestore.instance,
      storage: FirebaseStorage.instance,
    ),
    appId: 'my_flutter_app',
    environment: kReleaseMode ? 'production' : 'debug',
    userIdProvider: () => FirebaseAuth.instance.currentUser?.uid,
    userEmailProvider: () => FirebaseAuth.instance.currentUser?.email,
    routeProvider: () => AppRouteContext.instance.currentRoute,
    contextBuilder: () => AppRouteContext.instance.snapshot(),
  );
}
```

## Capture session context

Wire the current authenticated user and route into the shared client so ARM
case payloads include operator or end-user session context automatically:

- `userIdProvider`: stores the current UID in `context.userId`
- `userEmailProvider`: stores the current email in `context.userEmail`
- `routeProvider`: stores the current route in `context.route`
- `context.session`: stores the SDK-owned session block with the session id and
  the captured identity/route values

If `contextBuilder()` returns overlapping keys, the SDK's own session fields
win so `sessionId`, `userId`, `userEmail`, and `route` stay trustworthy.

## Capture unhandled failures

Wrap startup in `ArmBootstrap.runGuarded()`:

```dart
await ArmBootstrap.runGuarded(
  client: armClient,
  body: () async {
    runApp(MyApp(armClient: armClient));
  },
);
```

This captures:

- `FlutterError` failures
- `PlatformDispatcher` errors
- zone-level async exceptions

## Track risky operations

Use `runTracked()` around writes, submissions, import flows, payments, or onboarding steps where you want:

- consistent classification
- recovery snapshots
- an exposed case ID for user support

```dart
await armClient.runTracked<void>(
  feature: 'lead_capture',
  operation: 'submit_inquiry',
  severity: ArmSeverity.moderate,
  category: 'data_integrity',
  tags: <String, dynamic>{
    'projectSlug': projectSlug,
    'channel': selectedChannel,
  },
  recoverySnapshotBuilder: () => <String, dynamic>{
    'form': <String, dynamic>{
      'name': nameController.text.trim(),
      'email': emailController.text.trim(),
    },
  },
  action: () async {
    await repository.submitInquiry(...);
  },
  onReported: (result) {
    if (result.caseIdExposed) {
      debugPrint('Support reference: ${result.caseId}');
    }
  },
);
```

## Record handled exceptions directly

If you already have a catch block, call `captureException()`:

```dart
try {
  await syncJob.run();
} catch (error, stackTrace) {
  final result = await armClient.captureException(
    error: error,
    stackTrace: stackTrace,
    feature: 'background_sync',
    operation: 'pull_remote_state',
    severity: ArmSeverity.low,
    category: 'sync',
    handled: true,
  );

  debugPrint('ARM case: ${result.caseId}');
}
```

`captureException()` preserves the raw runtime error values in storage:
`errorType` comes from `error.runtimeType.toString()` and `message` comes from
`error.toString()`. Do not prepend custom labels to either field. If you need
extra classification, put it in `feature`, `operation`, `category`, or `tags`.

## Add screenshot capture

Wrap the relevant UI subtree:

```dart
final boundaryController = ArmCaptureBoundaryController();

ArmCaptureBoundary(
  controller: boundaryController,
  child: YourScreenBody(),
);
```

Pass the capture callback when reporting:

```dart
await armClient.runTracked<void>(
  feature: 'checkout',
  operation: 'submit_payment',
  severity: ArmSeverity.serious,
  category: 'ui_failure',
  screenshotCapture: boundaryController.capturePng,
  action: () async {
    await checkoutRepository.submit(...);
  },
);
```

If screenshot upload fails, the incident is still written to Firestore.

## Recommended severity model

Use a consistent severity convention across apps:

- `ArmSeverity.low` for diagnostics and non-blocking errors
- `ArmSeverity.moderate` for failed user actions or possible data loss
- `ArmSeverity.serious` for confirmed integrity risk, corrupted state, or major feature failure

## What gets written

`FirebaseArmSink` writes:

- one issue summary document per fingerprint in `armIssues`
- one case document per occurrence in `armCases`

The issue summary stays lightweight for client-side deduplication. Detailed diagnostics, recovery payloads, and screenshot metadata belong in the case record.

For case records, keep the captured error identity raw:

- `errorType` is the original runtime error name
- `message` is the original error payload text
- custom labels should not be baked into those fields
- `context.userId` / `context.userEmail` / `context.route` should be populated
  through the dedicated providers instead of being manually spoofed inside
  `contextBuilder()`

In Citadel deployments, remember the boundary:

- Citadel platform auth/registry metadata belongs in `citadel-platform`
- ARM telemetry for a monitored app belongs in that monitored app's own Firebase project
- screenshot uploads are optional and best-effort
