# @citadel/arm-web

ARM for the browser — Feature 1.6.2, on the Citadel Core SDK.

**Only the document contract exists so far:** the fingerprint, issue id and
sanitiser, ported from `arm/tooling_core` and held to
`arm/contract/conformance.json` (`npm test`). Error capture is not built,
because how browser evidence reaches the client's `citadel-arm` database is an
open decision: the ARM evidence service is private and has no ingest route or
ingest credential. See `DECISIONS_NEEDED.md`.
