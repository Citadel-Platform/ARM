# @citadel/arm-web

ARM for the browser — Feature 1.6.2, on the Citadel Core SDK. Sends to
Citadel's one shared ARM ingest, which groups what it receives and writes it
into the client's own `citadel-arm` (decided 23/09/26).

## Install

Core first, then ARM — both served by the ARM ingest:

```html
<script src="https://ARM_INGEST/sdk/v1/citadel-core.js"></script>
<script src="https://ARM_INGEST/sdk/v1/arm.js"
        data-client-id="CLIENT_ID" data-ingest-key="ARM_INGEST_KEY"
        data-release="2.3.0" data-environment="production"></script>
```

The three values come from Console → ARM → Set up ARM → *Issue the ingest key*.
A page that also runs Conduit loads `citadel-core.js` once.

npm: `init({ clientId, ingestKey, ingestUrl })`, then
`arm.captureException(error, { feature, operation, severity })`.

## What it captures

| Operation | What | Severity |
| --- | --- | --- |
| `window_error` | an uncaught error | serious |
| `unhandled_rejection` | a promise nobody caught | serious |
| `http_error` | 5xx, or a request that never completed, to a watched host | moderate / low |
| `resource_load` | an image, script or stylesheet that failed to load | low |
| `csp_violation` | the site's Content-Security-Policy blocked something | low |
| (yours) | `captureException` | low unless you say |

Every capture carries Core's session id and breadcrumbs, the release and
environment, and the page address without its query string. **URLs inside a
stack or message lose their query too** — an inline script's frame names the
page it ran on, and a reset token was seen reaching the database that way
before this was added.

A repeat of one fault within a minute is counted and carried on the next
report rather than sent (the Flutter SDK's rule), and a page sends at most 30.

## The contract

`@citadel/arm-contract` (`arm/contract/js`) is `arm/tooling_core`'s
fingerprint and sanitiser, held to `arm/contract/conformance.json` by its own
`npm test`, and shared with `@citadel/arm-node`. The ingest computes the
fingerprint that is stored; this copy only recognises a repeat on the page.

## Not yet

No source-map symbolication; no release-health session counts (Feature 1.6.2);
not deployed. See `citadel_docs/operator/10-known-limits.md`.
