# Current State

## DashboardUI

`DashboardUI` uses the local Citadel ARM SDK through a path dependency in:

- [DashboardUI/pubspec.yaml](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/DashboardUI/pubspec.yaml:50)

ARM bootstrapping and client wiring live in:

- [DashboardUI/lib/main.dart](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/DashboardUI/lib/main.dart:95)
- [DashboardUI/lib/arm/arm.dart](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/DashboardUI/lib/arm/arm.dart:1)

The dashboard currently relies on the shared SDK for:

- guarded Flutter error capture
- Firestore issue/case persistence
- screenshot capture boundaries
- breadcrumbs
- issue fingerprinting

The dashboard keeps local middleware only for:

- route integration via `NavigatorObserver`
- app-specific ARM client initialization
- linked server failure handling through `ArmLinkedServerFailure`
- avoiding duplicate local ARM captures when the server already returned an ARM case ID

The dashboard no longer adds the old local raw-error adapter behavior such as:

- `rawErrorName`
- `rawErrorData`
- injected `rawError` recovery snapshots

## LAD_Server

`LAD_Server` still uses a custom ARM reporter in:

- [LAD_Server/lad_server/lib/arm_monitoring.dart](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/LAD_Server/lad_server/lib/arm_monitoring.dart:1)
- [LAD_Server/lad_server/lib/lad_server.dart](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/LuminaryAxisDashboard/LAD_Server/lad_server/lib/lad_server.dart:24)

The shared ARM SDK now provides the missing server-side surface in:

- [../CitadelPlatform/citadel_core/arm/tooling_core](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/CitadelPlatform/citadel_core/arm/tooling_core)
- [../CitadelPlatform/citadel_core/arm/tooling_server](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/CitadelPlatform/citadel_core/arm/tooling_server)

That new shared server facet now covers:

- a pure-Dart shared contract layer
- a service-account Firestore sink
- request middleware / wrapper helpers
- server request context capture
- server-side structured exception normalization
- ARM case-ID response helpers

`LAD_Server` itself has not yet been migrated to consume those packages, so
the local reporter still exists there for now.

## Shared SDK Source

The local SDK source currently used by `DashboardUI` is:

- [../CitadelPlatform/citadel_core/arm/tooling](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/CitadelPlatform/citadel_core/arm/tooling)

The broader shared ARM SDK tree is now:

- [../CitadelPlatform/citadel_core/arm/tooling_core](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/CitadelPlatform/citadel_core/arm/tooling_core)
- [../CitadelPlatform/citadel_core/arm/tooling](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/CitadelPlatform/citadel_core/arm/tooling)
- [../CitadelPlatform/citadel_core/arm/tooling_server](/Users/OBSiDIAN/Downloads/Shelves/VSCode/Repositories/CitadelPlatform/citadel_core/arm/tooling_server)
