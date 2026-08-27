# Citadel ARM

Automated Remote Monitoring (ARM) is the first consolidated Citadel Platform product line.

## Packages

- `tooling_core/` — pure-Dart shared ARM primitives: severity models,
  fingerprinting, sanitization, ID generation, and shared issue/case document
  builders.
- `tooling/` — Flutter package embedded in monitored client apps. It captures
  handled and unhandled failures, breadcrumbs, recovery snapshots, optional
  screenshots, issue fingerprints, and case records in the client's own
  Firebase project.
- `tooling_server/` — server/runtime ARM package with service-account
  Firestore persistence, guarded server capture, request context helpers, and
  normalized server error reporting.

## Consolidation note

The ARM SDK is now split by runtime concern: shared contracts live in
`tooling_core`, Flutter capture lives in `tooling`, and server-side capture
and service-account sinks live in `tooling_server`. The standalone ARM Console
is retired; the unified Citadel Platform Console is the only production UI for
ARM workflows. Consuming apps should depend only on the runtime facet they
actually use.
