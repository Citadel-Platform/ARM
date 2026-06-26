# Installation Guide

This guide covers the minimum setup for using `arm_tooling` with the included Firebase sink inside the Citadel ARM model.

For server-side capture, use `arm_tooling_server` instead. `arm_tooling`
remains the Flutter/client facet, backed internally by the shared
`arm_tooling_core` package.

## 1. Add dependencies

In your app's `pubspec.yaml`:

```yaml
dependencies:
  arm_tooling: ^0.1.0
  firebase_core: ^3.15.2
  cloud_firestore: ^5.6.12
  firebase_storage: ^12.4.10
```

Then install packages:

```sh
flutter pub get
```

## 2. Enable Firebase services

The bundled `FirebaseArmSink` expects:

- Cloud Firestore for issue and case documents
- Firebase Storage only if you want screenshot uploads

Recommended document layout in the monitored application's own Firebase project:

- `armIssues/{issueId}` for deduplicated issue summaries
- `armCases/{caseId}` for full incident details

## 3. Configure Firebase for your app

Initialize Firebase before creating the ARM client:

```dart
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp();
```

For Flutter web, generate your `firebase_options.dart` using FlutterFire or provide explicit `FirebaseOptions`.
For Citadel-owned apps, register the consuming Firebase app under the
`citadel-platform` project instead of reusing the ARM console's credentials.

## 4. Add security rules

Your app needs Firestore rules that allow:

- client writes to `armCases`
- client reads and writes to the minimal `armIssues` summary documents used for deduplication
- restricted reads for full incident detail

If you enable screenshot uploads, add Firebase Storage rules that allow the client to write screenshots under your chosen ARM path, such as `arm/cases/{caseId}/...`.

## 5. Create a shared ARM client

```dart
final armClient = ArmClient(
  sink: FirebaseArmSink(
    firestore: FirebaseFirestore.instance,
    storage: FirebaseStorage.instance,
  ),
  appId: 'my_app',
  environment: kReleaseMode ? 'production' : 'debug',
  userIdProvider: () => FirebaseAuth.instance.currentUser?.uid,
  userEmailProvider: () => FirebaseAuth.instance.currentUser?.email,
);
```

If you have route context available, also pass `routeProvider` so ARM can tie
case records to the current screen or flow. The SDK persists these values under
the case `context` map and groups them under `context.session` automatically.

## 6. Wrap app startup

Use `ArmBootstrap.runGuarded()` so unhandled startup and runtime failures are captured:

```dart
await ArmBootstrap.runGuarded(
  client: armClient,
  body: () async {
    runApp(MyApp(armClient: armClient));
  },
);
```

## 7. Verify with the example app

The package currently ships without a checked-in example app in this monorepo, so validate integration by wiring `ArmBootstrap.runGuarded()` into a real Flutter host app and forcing a handled and unhandled failure in local/dev mode.
