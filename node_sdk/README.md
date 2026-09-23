# @citadel/arm-node

ARM for Node servers (Feature 1.6.3). Captures uncaught exceptions, unhandled
rejections, 5xx answers and slow requests, and sends them to Citadel's shared
ARM ingest with the client id and ARM ingest key. The ingest groups them and
writes the client's own `citadel-arm`; this package never touches Firestore.

## Install

From the ARM ingest (not published to npm):

```bash
npm install https://<arm-ingest>/sdk/v1/arm-node.tgz
```

```js
import { init, armRequestHandler, armErrorHandler } from '@citadel/arm-node';

const arm = init({
  clientId: 'CLIENT_ID',          // ARM → Set up ARM → Issue the ingest key
  ingestKey: 'ARM_INGEST_KEY',
  ingestUrl: 'https://<arm-ingest>',
  release: process.env.RELEASE,   // optional
  environment: 'production',      // optional
  service: 'api',                 // optional: what this process is
});

// Express: first, and after the routes.
app.use(armRequestHandler(arm, { slowMs: 3000 }));
// ...routes...
app.use(armErrorHandler(arm));
```

- **Fastify:** `fastify.register(armFastify(arm))`.
- **Next.js:** in `instrumentation.ts`,
  `export const onRequestError = armNextOnRequestError(arm)`.
- **Anything else:** `arm.captureException(error, { feature, operation })`.

## What it will not do

- **Change how the process dies.** With no other `uncaughtException` handler,
  it captures, waits up to 2 s for the capture to leave, prints the error as
  Node would and exits 1. With one, the application stays in charge and ARM
  only watches.
- **Hold the process open, block a request, or throw into the host.** Sending
  is batched off the request path on an unreferenced timer; an unreachable
  ingest costs a bounded request per batch.
- **Send a header, cookie, body or query string.** A request contributes its
  method, route pattern, path, status and duration. Stack paths under `root`
  (default `process.cwd()`) are sent relative to it.

## Development

`npm test` — against a real local HTTP server, with the fatal paths in real
child processes. `npm run pack:release -- out.tgz` — the installable tarball,
`@citadel/arm-contract` inlined.
