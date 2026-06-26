# arm_tooling

`arm_tooling` is the reusable Citadel ARM Flutter SDK for low-overhead
automated remote monitoring in deployed apps.

The ARM SDK is now split by runtime concern:

- `arm_tooling_core` holds the shared pure-Dart capture models, sanitization,
  fingerprinting, and document builders.
- `arm_tooling` is the Flutter/client package described here.
- `arm_tooling_server` provides the server-side reporter, request helpers, and
  service-account Firestore sink.

It captures handled and unhandled failures, fingerprints recurring issues, stores per-incident cases in Cloud Firestore, and can attach screenshots through Firebase Storage. It is designed for Flutter web and mobile apps that want production telemetry without introducing a custom server just for crash and incident intake.

## Features

- Captures `FlutterError`, `PlatformDispatcher`, and zone-level async failures.
- Records breadcrumb history from nearby app events and `print()` output.
- Deduplicates related failures into stable issue IDs.
- Stores per-occurrence cases with context, tags, and optional recovery snapshots.
- Optionally uploads screenshots to Firebase Storage.
- Returns a case ID for moderate-or-higher incidents so apps can show a support reference to the user.

## Documentation

- [Installation guide](doc/installation.md)
- [Usage guide](doc/usage.md)

## Installation

Add the package to your app:

```yaml
dependencies:
  arm_tooling: ^0.1.0
```

If your app does not already use them, add the Firebase packages required by your chosen sink:

```yaml
dependencies:
  firebase_core: ^3.15.2
  cloud_firestore: ^5.6.12
  firebase_storage: ^12.4.10
```

Then fetch dependencies:

```sh
flutter pub get
```

## Firebase setup

`arm_tooling` is intentionally storage-agnostic at the API layer, but the included `FirebaseArmSink` expects:

1. Firebase to be initialized before use.
2. Cloud Firestore to be enabled.
3. Firebase Storage to be enabled only if you want screenshot uploads.
4. Security rules in the consuming app that allow:
   - case writes from the client
   - issue-summary reads and writes for deduplication
   - admin-only reads for full incident details

Recommended collections:

- `armIssues/{issueId}`: lightweight deduplicated issue summary.
- `armCases/{caseId}`: full incident records with breadcrumbs, stack traces, snapshots, and optional screenshot metadata.

For Citadel usage, platform-owned auth, registry, and operator metadata stay in
the shared `citadel-platform` Firebase project, while monitored application
telemetry stays in the monitored app's own Firebase project. `arm_tooling`
writes only to the monitored application's boundary.

## Quick start

Create a shared `ArmClient`:

```dart
import 'package:arm_tooling/arm_tooling.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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

When `userIdProvider`, `userEmailProvider`, or `routeProvider` are configured,
the SDK injects those values into every case payload automatically. ARM stores
them in `context.userId`, `context.userEmail`, and `context.route`, and also
groups the SDK-owned session metadata under `context.session`.

Wrap app startup so unhandled failures are captured:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final armClient = createArmClient();

  await ArmBootstrap.runGuarded(
    client: armClient,
    body: () async {
      runApp(MyApp(armClient: armClient));
    },
  );
}
```

For Citadel-owned apps, register the consuming Firebase app under the
`citadel-platform` project and initialize ARM using that app's generated client
config.

Expose the client through your app's dependency injection:

```dart
return Provider<ArmClient>.value(
  value: armClient,
  child: const MyRootView(),
);
```

## Tracking a risky operation

Use `runTracked()` around writes, submissions, checkout steps, or any action where you want a case ID and recovery context if something fails:

```dart
final armClient = context.read<ArmClient>();

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

## Adding screenshot capture

Wrap the part of the UI you want to capture in `ArmCaptureBoundary` and pass the controller's `capturePng` callback to `runTracked()` or `captureException()`:

```dart
final boundaryController = ArmCaptureBoundaryController();

ArmCaptureBoundary(
  controller: boundaryController,
  child: YourScreenBody(),
);
```

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

Screenshot uploads are best-effort. If Storage is not configured or the upload fails, the case is still recorded in Firestore.

## Capturing handled exceptions directly

If you already have a catch block and want to record the exception explicitly:

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

ARM stores the raw exception identity in the case document: `errorType` is taken
directly from `error.runtimeType.toString()` and `message` from
`error.toString()`. Do not wrap either with custom labels such as
`CheckoutError: ...`; keep any app-specific classification in `feature`,
`operation`, `category`, or `tags`.

## ARM data contract

`FirebaseArmSink` writes:

- an issue summary document keyed by fingerprint hash
- a case document per occurrence

The issue summary is intentionally lightweight so the client can perform deduplication checks without exposing full stack traces or recovery payloads. Full diagnostic detail stays in the case document.

Issue summary fields in `armIssues/{issueId}`:

- `issueId`
- `severity`
- `category`
- `feature`
- `operation`
- `firstSeenAt`
- `lastSeenAt`
- `firstCaseId`
- `lastCaseId`
- `caseCount`

Case fields in `armCases/{caseId}`:

- `caseId`
- `issueId`
- `fingerprint`
- `severity`
- `category`
- `feature`
- `operation`
- `message`
- `errorType`
- `stackTrace`
- `sessionId`
- `handled`
- `context`
- `tags`
- `breadcrumbs`
- optional `recoverySnapshot`
- optional `screenshot.path`
- optional `screenshot.contentType`
- `createdAt`

Error field rules:

- `errorType` must remain the raw error name from `error.runtimeType.toString()`
- `message` must remain the raw error payload from `error.toString()`
- custom labels or app-specific prefixes belong in `feature`, `operation`,
  `category`, or `tags`, not in `errorType` or `message`

Context field rules:

- `context.sessionId` is always written by the SDK
- `context.userId` is written when `userIdProvider` returns a non-empty value
- `context.userEmail` is written when `userEmailProvider` returns a non-empty
  value
- `context.route` is written when `routeProvider` returns a non-empty value
- `context.session` contains the SDK-owned session block with `id`, `appId`,
  `environment`, `releaseMode`, and any captured `userId`, `userEmail`, or
  `route`
- SDK-owned keys stay authoritative even if `contextBuilder()` returns the same
  field names

Screenshot storage path:

- `${screenshotPrefix}/{issueId}/{caseId}/{attachmentName}.{extension}`
- default prefix: `arm/cases`

Schema evolution rule:

- add fields additively
- do not rename or remove existing fields without a migration path
- keep old cases readable even if newer clients emit more context
