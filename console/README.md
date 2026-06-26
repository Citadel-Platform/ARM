# ARM Console

This project is a Flutter web app designed to be used to view logs, telemetry, issues, and cases recorded by the ARM Tooling package, which is located at: https://pub.dev/packages/arm_tooling.

## Automated Remote Monitoring (ARM) Tooling

ARM Tooling is a feature that I use for deployed web apps, to allow telemetry collection and for automated error or bug reporting. It can:
- trace errors or bugs down to the specific file and method (which is usually not possible in production due to o0bfuscation)
- log those traces, console logs and errors whenever an issue occurs to Firestore
- collect relevant state/context information
- if the issue is pertaining a visual/UI problem, capture a screenshot and store in GCS
- stack related or the same problems together. so if it sees the same issue is already logged in Firestore, then the telemetry just gets added as evidence, and reported as a separate case, not separate issue.
- when a moderate-to-serious issue occurs (pertaining data integrity), the case ID is displayed to the end-user so they can follow up.
- prevent data corruption or loss perhaps through periodic snapshots or by saving snapshots of the relevant data only when an issue is detected. e.g if the user is inputting a student's onboarding details via the form and an error occurs with network or the server, the inputted data is snapshotted and logged in Firestore for recovery later, with the respective context and instructions
- minimise the bloat, compute overhead, and latency added to the app itself

## The ARM Console for Admin/Dev Use

The ARM console will provide a UI for the superuser (myself), project-scoped developers, and project-scoped viewers to log in and view:
- logged cases
- reports/dashboards/metrics
- snapshots/screenshots and supporting data for logged cases

It will not modify monitored project telemetry or evidence data. The console uses the shared `citadel-platform` Firebase project for console-specific data such as Firebase Auth, project registry records, and scoped role assignments. Every monitored client project still stores its own ARM telemetry and evidence data in that client's own Firestore and Storage resources.

The app will allow me to add projects:
- each project configuration that I input will have the Firebase creds to access and pull ARM data from that project's Firestore/Storage
- I can configure project-scoped developer and viewer email accounts for each project. Developers are intended for editable project data flows, viewers are read-only, and only the single superuser account can access every project and manage the console registry itself.

Ensure I have a bird's eye view when needed (not just meaningless metrics) to keep urgent information topmost, but also can dive into specific object data.

## Console Auth Setup

Feature 1.2 uses Firebase Auth for sign-in and a console-owned Firestore collection for admin project scope lookup inside the shared `citadel-platform` Firebase project.

### Required local Firebase values

Provide these through local build configuration so `lib/firebase_options.dart` can construct `FirebaseOptions` safely:

- `ARM_CONSOLE_FIREBASE_API_KEY`
- `ARM_CONSOLE_FIREBASE_APP_ID`
- `ARM_CONSOLE_FIREBASE_MESSAGING_SENDER_ID`
- `ARM_CONSOLE_FIREBASE_PROJECT_ID`

For this workspace, `ARM_CONSOLE_FIREBASE_PROJECT_ID` should be
`citadel-platform`. The other client values must come from the ARM console's
Firebase web app registered under that shared platform project; they cannot be
derived from the GCP project ID alone.

Optional values:

- `ARM_CONSOLE_FIREBASE_AUTH_DOMAIN`
- `ARM_CONSOLE_FIREBASE_DATABASE_URL`
- `ARM_CONSOLE_FIREBASE_STORAGE_BUCKET`
- `ARM_CONSOLE_FIREBASE_MEASUREMENT_ID`
- `ARM_CONSOLE_FIREBASE_IOS_BUNDLE_ID`
- `ARM_CONSOLE_FIREBASE_ANDROID_CLIENT_ID`
- `ARM_CONSOLE_FIREBASE_IOS_CLIENT_ID`

If these values are absent, the app stays in a local fallback mode and shows an explicit sign-in unavailable message instead of crashing.

### Local `.env` helper

The repo expects local secrets to live in `.env`. If your local file already uses the shorter `FB_*` keys, use the helper below so Flutter receives the expected `ARM_CONSOLE_FIREBASE_*` dart-defines without copying values into tracked files:

```bash
bash tool/flutter_with_console_env.sh run -d chrome
```

The helper only forwards the console Firebase client fields. It does not inject unrelated `.env` values.

### Firebase Hosting deploy

If you see `Sign-in is unavailable because Firebase credentials are not configured.`, the app was built without the required `ARM_CONSOLE_FIREBASE_*` dart-defines and fell back to the local in-memory auth gateway.

For this repo, build and deploy the web app through the helper so the Firebase web config from `.env` is injected into the release build:

```bash
bash tool/deploy_firebase_hosting.sh
```

That script:

- runs `flutter build web --release` with the required Firebase client values from `.env`
- deploys the generated `build/web` bundle to Firebase Hosting with the Firebase CLI

If you prefer to split the steps manually:

```bash
bash tool/flutter_with_console_env.sh build web --release
npx -y firebase-tools@latest deploy --only hosting
```

Because the app uses path URLs on web, `firebase.json` must rewrite all routes to `index.html` for deep links and refreshes to keep working on Hosting.

### Firebase Auth checks for hosted sign-in

Before testing Google sign-in on the hosted site:

- enable Google as a sign-in provider in Firebase Authentication
- make sure the hosted origin is in Firebase Auth authorized domains, especially if you use a custom domain
- keep `FB_AUTH_DOMAIN` aligned with the Firebase Auth domain you want the web SDK to use
- for this repo, source that auth domain from the Firebase app registered under `citadel-platform`

### Monitored-project prep

Use the interactive helper below when you are bringing a monitored client Firebase project online for ARM telemetry:

```bash
dart tool/prepare_monitored_projects.dart
```

For each target project, the script:

- confirms the Firebase client config needed by the monitored app is present
- checks and offers to enable the Firebase / Google Cloud APIs needed for Firestore, Storage, and Auth
- checks whether the default Firestore database exists and offers to create it when missing
- checks the configured Cloud Storage bucket and offers to create it when missing
- explains each action before it runs and asks for confirmation before any change is made

### Simple compatibility check

If you only want a local read-only check that you can copy into any project directory, use:

```bash
bash tool/check_arm_firebase_config.sh
```

That script verifies the project's Firebase client config values, checks that Firestore rules are present, and checks that Firestore and Storage rules are not obviously public. It will auto-detect a nearby `options.dart` or `firebase_options.dart` file if one exists, and you can point it at a specific Dart file with `--dart-file PATH`. It does not enable APIs, create databases, or mutate Firebase resources, and its rules audit is intentionally conservative: it fails obvious public access patterns and warns when it cannot confirm a standard auth guard.

### Optional local UI preview

When you want to iterate on the shell and page UI without wiring live Firebase first, run the app with:

- `--dart-define=ARM_CONSOLE_ENABLE_LOCAL_DEV_SESSION=true`

That enables a superuser-scoped in-memory session and seeds a few local projects so the routed shell, switcher, and project directory can be previewed immediately.
The current preview seed set mirrors the shared Citadel sample ids used across the platform surfaces: `core-platform`, `customer-ops`, and `innovation-lab`.

## Project Registry Setup

Feature 1.2 stores console-owned configuration in the shared `citadel-platform` Firestore project so monitored projects can be listed, selected, and validated without touching their evidence data.

### Current registry contract

- Project records live in `console_projects/{projectId}`.
- Each record stores:
  - `name`
  - `environment`
  - `firebase` client config fields used to connect to the monitored client's Firebase project
  - `developerEmails`
  - `viewerEmails`
  - `createdAt`, `updatedAt`, `createdBy`, `updatedBy`
  - `isReadOnlyConsole`
  - `connection` validation summary fields
- Project ids are slug-style, lowercase, and hyphenated.
- Saving a project also updates the affected `console_access/{normalizedEmail}` documents so scoped role assignments stay in sync with the registry.

### Current validation behavior

- Validation is read-only.
- The console checks required Firebase client fields first.
- When live Firebase access is available, the console initializes a secondary app against the monitored client's Firebase config and performs a Firestore read probe plus a Storage probe when a bucket is configured.
- Validation never writes to monitored-project telemetry, cases, screenshots, snapshots, or other ARM evidence data.

### Current access model

- Google Sign-In is the initial provider for console access.
- Superuser access is granted by a Firebase Auth custom claim. The current client implementation treats any of `arm_console_superuser`, `armConsoleSuperuser`, or `superuser` as the superuser flag when truthy.
- Project-scoped developer and viewer roles are read from the console Firestore collection `console_access`.
- The canonical document shape is keyed by normalized email and stores `developerProjectIds`, `viewerProjectIds`, and union `projectIds`. Legacy `projectIds` or `projects` arrays are still read as viewer fallback.
- Project-scoped reads into the console's own registry stay limited to those assigned project ids; only the superuser gets global cross-project scope and registry writes. Separate monitored-project reads still target the external client Firebase project configured for that project.

## Firestore Rules And Bootstrap

- The repo now includes `firestore.rules` and `firebase.json` points the Firebase CLI at that ruleset.
- Rules currently support one bootstrap superuser email, `obsidian.infinitum@gmail.com`, in addition to the existing custom-claim path. That bootstrap owner must still have a verified Google account.
- Use the helper below to seed `console_projects` and the matching `console_access/{email}` doc from the local `projects.json` file without copying secrets into tracked files:

```bash
node tool/bootstrap_console_firestore.mjs
```

- The helper reads `.env` for the console Firebase client config, uses the active `gcloud` account email as the bootstrap email by default, serves a one-time local page, and writes the seeded registry plus scoped access docs after a Google popup sign-in.
- `projects.json` now targets `citadel-platform`; replace its placeholder web-app values with the real Firebase client config before using the bootstrap helper.

## Firebase Custom Claims

- The console superuser role is primarily driven by Firebase Auth custom claims.
- To grant a user the superuser role, first configure Application Default Credentials:

```bash
gcloud auth application-default login
```

- If you already have a service-account JSON with Firebase Auth admin access, you can point `GOOGLE_APPLICATION_CREDENTIALS` at that file instead.
- Then set the claim with the helper below:

```bash
bash tool/set_console_claims.sh \
  --project citadel-platform \
  --email obsidian.infinitum@gmail.com \
  --claim arm_console_superuser \
  --value true
```

- The helper merges with the user's existing custom claims instead of replacing them.
- After updating claims, sign out and back in, or force an ID token refresh in the client.
