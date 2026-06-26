# ARM SDK Migration Notes

This folder captures the current ARM migration state for `LuminaryAxisDashboard`.

Files:

- `current-state.md`
  Current client/server ARM setup, including what now uses the local Citadel SDK.
- `replacement-tradeoffs.md`
  What would be lost or preserved if the local middleware were removed and the codebase used only the shared SDK.
- `server-sdk-requirements.md`
  What the shared SDK would need in order to replace `LAD_Server` feature-wise.

Current practical state:

- `DashboardUI` now resolves `arm_tooling` from the local Citadel source tree.
- `DashboardUI` keeps a thin local ARM wrapper only for app wiring and server-case linking.
- The shared Citadel SDK now exposes:
  - `arm_tooling_core` for shared ARM contracts and helpers
  - `arm_tooling` for Flutter/client capture
  - `arm_tooling_server` for server capture, service-account Firestore writes,
    request context, and case-linking response helpers
- `LAD_Server` still uses its local ARM reporter today, but the shared SDK now
  provides the feature surface required to migrate it off that custom
  implementation.
