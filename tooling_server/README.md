# arm_tooling_server

`arm_tooling_server` is the server/runtime facet of the Citadel ARM SDK.

It provides:

- service-account Firestore persistence for `armIssues` and `armCases`
- guarded server capture helpers
- HTTP request context capture
- structured server exception normalization
- ARM case-ID response helpers for linked client/server incident flows

See [doc/usage.md](doc/usage.md) for the main integration patterns.
