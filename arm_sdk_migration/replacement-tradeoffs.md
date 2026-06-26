# Replacement Tradeoffs

## If DashboardUI used only the shared SDK

The dashboard would keep the core client ARM behavior because that already comes from the SDK:

- global Flutter / zone / platform failure capture
- Firestore issue/case writes
- screenshot capture support
- breadcrumbs and `print()` capture
- issue fingerprinting and case IDs

The dashboard would lose useful local integration behavior unless it was re-added:

- `ArmLinkedServerFailure`
- transport-level server-case linking through `x-arm-case-id`
- duplicate-capture suppression when the backend already reported the incident
- app-specific route observer glue

So the correct model is not “SDK only.” The correct model is:

- shared SDK for client telemetry primitives
- thin local wrapper for app wiring and server-linking semantics

## If LAD_Server were switched to the shared SDK today

That would be a regression, not an upgrade.

The current shared SDK is a Flutter/client package. It does not ship:

- a pure Dart server client
- a backend Firestore sink using service-account auth
- request guards / middleware
- request context capture
- server exception normalization

If the current server ARM code were removed today, the backend would lose:

- ARM case creation for server failures
- request context capture
- structured backend exception data
- server ARM case IDs returned to the dashboard
- client/server incident linking

## Practical conclusion

The dashboard can and should consume the shared SDK.

The server cannot be replaced by the shared SDK until the SDK grows a dedicated server layer.
