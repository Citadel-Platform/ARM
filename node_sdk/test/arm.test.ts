import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { createServer, type IncomingMessage, type Server } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { ArmNode, armErrorHandler, armRequestHandler } from '../src/index.js';

/**
 * Everything here runs against a real HTTP server standing in for the ingest
 * — it records what arrives and answers what it is told to — and the fatal
 * paths run in real child processes, because "exits 1 after sending" is a
 * claim about a process, not about a function.
 */

interface Received {
  headers: IncomingMessage['headers'];
  body: Array<Record<string, unknown>>;
}
let ingest: Server;
let ingestUrl = '';
const received: Received[] = [];
let answer = 202;

before(async () => {
  ingest = createServer((req, res) => {
    let data = '';
    req.on('data', (chunk) => (data += chunk));
    req.on('end', () => {
      received.push({ headers: req.headers, body: JSON.parse(data) as Array<Record<string, unknown>> });
      res.writeHead(answer, { 'content-type': 'application/json' }).end('{}');
    });
  });
  await new Promise<void>((resolve) => ingest.listen(0, '127.0.0.1', resolve));
  const address = ingest.address();
  ingestUrl = `http://127.0.0.1:${typeof address === 'object' && address !== null ? address.port : 0}`;
});
after(() => ingest.close());

function client(extra: Partial<ConstructorParameters<typeof ArmNode>[0]> = {}): ArmNode {
  received.length = 0;
  answer = 202;
  return new ArmNode({
    clientId: 'client-a',
    ingestKey: 'arm-client-a-key',
    ingestUrl,
    release: '1.4.0',
    environment: 'production',
    service: 'api',
    root: '/srv/app',
    installProcessHandlers: false,
    ...extra,
  });
}

test('a caught error is sent as a node capture, with the key in headers', async () => {
  const arm = client();
  const error = new TypeError('Order 9817 not found');
  error.stack = 'TypeError: Order 9817 not found\n    at load (/srv/app/src/orders.js:12:5)\n    at file:///srv/app/src/server.mjs:40:3';
  const id = arm.captureException(error, { feature: 'orders', operation: 'load', request: { method: 'get', route: '/orders/:id', path: '/orders/9817?token=secret', status: 500 } });
  assert.ok(id);
  await arm.close();

  assert.equal(received.length, 1);
  const { headers, body } = received[0]!;
  assert.equal(headers['x-citadel-client'], 'client-a');
  assert.equal(headers['x-arm-key'], 'arm-client-a-key');
  const capture = body[0]!;
  assert.equal(capture.source, 'node');
  assert.equal(capture.errorType, 'TypeError');
  assert.equal(capture.feature, 'orders');
  assert.equal(capture.appVersion, '1.4.0');
  assert.equal(capture.environment, 'production');
  assert.match(String(capture.sessionId), /^proc-/);
  // Paths under the root go relative; nothing of the server's layout leaves.
  assert.equal(capture.stackTrace, 'TypeError: Order 9817 not found\n    at load (src/orders.js:12:5)\n    at src/server.mjs:40:3');
  const request = (capture.context as Record<string, unknown>).request as Record<string, unknown>;
  assert.deepEqual(request, { method: 'GET', route: '/orders/:id', path: '/orders/9817', status: 500 });
  assert.doesNotMatch(JSON.stringify(body), /secret/);
});

test('a root reached through a symlink matches frames named by the resolved path', async () => {
  const { mkdtempSync, mkdirSync, symlinkSync } = await import('node:fs');
  const base = mkdtempSync(join(tmpdir(), 'arm-root-'));
  mkdirSync(join(base, 'releases', 'r42'), { recursive: true });
  symlinkSync(join(base, 'releases', 'r42'), join(base, 'current'));
  const arm = client({ root: join(base, 'current') });
  const resolved = realpathSync(join(base, 'releases', 'r42'));
  assert.equal(arm.relativeStack(`at f (${resolved}/src/a.js:1:2)`), 'at f (src/a.js:1:2)');
  await arm.close();
});

test('a repeat inside the minute is counted and reported with the next one', async () => {
  const arm = client();
  const fault = () => new Error('boom');
  assert.ok(arm.captureException(fault(), { operation: 'x' }));
  assert.equal(arm.captureException(fault(), { operation: 'x' }), null);
  assert.equal(arm.captureException(fault(), { operation: 'x' }), null);
  assert.ok(arm.captureException(new Error('different'), { operation: 'x' }));
  await arm.close();
  assert.equal(received.flatMap((r) => r.body).length, 2);
});

test('the per-minute cap holds', async () => {
  const arm = client({ maxCapturesPerMinute: 3 });
  for (let i = 0; i < 10; i += 1) arm.captureException(new Error(`fault kind ${String.fromCharCode(97 + i)}`));
  await arm.close();
  assert.equal(received.flatMap((r) => r.body).length, 3);
});

test('a refused key is not retried; a failing ingest is, then given up on', async () => {
  let arm = client();
  answer = 401;
  arm.captureException(new Error('a'));
  await arm.close();
  assert.equal(received.length, 1, '401 will not get better by asking again');

  arm = client();
  answer = 503;
  arm.captureException(new Error('b'));
  await arm.close(10_000);
  assert.equal(received.length, 3, 'three attempts, then dropped');
});

test('an unreachable ingest costs nothing the host can see', async () => {
  const arm = client({ ingestUrl: 'http://127.0.0.1:9' });
  assert.ok(arm.captureException(new Error('offline')));
  const started = Date.now();
  await arm.close(1000);
  assert.ok(Date.now() - started < 1500);
});

test('Express-style: an error is captured once, a 5xx without one is captured, a slow answer is reported', async () => {
  const arm = client();
  const onRequest = armRequestHandler(arm, { slowMs: 50 });
  const onError = armErrorHandler(arm);
  const app = createServer((req, res) => {
    onRequest(req as never, res as never, () => undefined);
    if (req.url?.startsWith('/throws')) {
      const fakeReq = Object.assign(req, { route: { path: '/throws/:id' }, baseUrl: '' });
      onError(new RangeError('bad id'), fakeReq as never, res, () => {
        res.statusCode = 500;
        res.end('error');
      });
    } else if (req.url === '/fails') {
      res.statusCode = 502;
      res.end('upstream');
    } else {
      setTimeout(() => res.end('slow'), 80);
    }
  });
  await new Promise<void>((resolve) => app.listen(0, '127.0.0.1', resolve));
  const port = (app.address() as { port: number }).port;
  for (const path of ['/throws/7?x=1', '/fails', '/slow']) await fetch(`http://127.0.0.1:${port}${path}`).then((r) => r.text());
  app.close();
  await arm.close();

  const captures = received.flatMap((r) => r.body);
  const operations = captures.map((c) => c.operation).sort();
  assert.deepEqual(operations, ['http_5xx', 'request_error', 'slow_request']);
  const thrown = captures.find((c) => c.operation === 'request_error')!;
  assert.equal(thrown.errorType, 'RangeError');
  assert.deepEqual((thrown.context as Record<string, unknown>).request, { method: 'GET', route: '/throws/:id', path: '/throws/7' });
  const fivexx = captures.find((c) => c.operation === 'http_5xx')!;
  assert.equal(fivexx.message, 'GET /fails answered 502');
  assert.equal(fivexx.errorType, 'HttpError', 'the same name arm-web and arm-php use');
  assert.equal(captures.find((c) => c.operation === 'slow_request')!.errorType, 'SlowRequest');
});

// ------------------------------------------------------------ real processes

const distIndex = fileURLToPath(new URL('../src/index.js', import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'arm-node-'));

function run(script: string): Promise<{ code: number | null; stderr: string; ms: number }> {
  const file = join(dir, `s${Math.random().toString(36).slice(2)}.mjs`);
  writeFileSync(file, `import { init } from ${JSON.stringify(distIndex)};\n${script}`);
  const started = Date.now();
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [file], { env: { ...process.env, INGEST: ingestUrl } });
    let stderr = '';
    child.stderr.on('data', (d) => (stderr += d));
    child.on('exit', (code) => resolve({ code, stderr, ms: Date.now() - started }));
  });
}

test('an uncaught exception is sent, printed, and still exits 1', async () => {
  received.length = 0;
  answer = 202;
  const result = await run(`
    init({ clientId: 'client-a', ingestKey: 'k', ingestUrl: process.env.INGEST, service: 'worker' });
    setTimeout(() => { throw new SyntaxError('config is broken'); }, 10);
  `);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /SyntaxError: config is broken/);
  const capture = received.flatMap((r) => r.body)[0]!;
  assert.equal(capture.operation, 'uncaught_exception');
  assert.equal(capture.severity, 'critical');
  assert.equal(capture.feature, 'worker');
});

test('an unhandled rejection reaches the same path, and Node still exits 1', async () => {
  received.length = 0;
  const result = await run(`
    init({ clientId: 'client-a', ingestKey: 'k', ingestUrl: process.env.INGEST });
    Promise.reject(new Error('nobody awaited me'));
  `);
  assert.equal(result.code, 1);
  assert.equal(received.flatMap((r) => r.body)[0]!.operation, 'unhandled_rejection');
});

test('with the ingest unreachable, a fatal exits 1 within the flush timeout', async () => {
  const result = await run(`
    init({ clientId: 'client-a', ingestKey: 'k', ingestUrl: 'http://10.255.255.1:81', fatalFlushTimeoutMs: 500 });
    setTimeout(() => { throw new Error('offline fatal'); }, 10);
  `);
  assert.equal(result.code, 1);
  assert.ok(result.ms < 3000, `took ${result.ms} ms`);
});

test("an application's own handler keeps control; ARM only watches", async () => {
  received.length = 0;
  const result = await run(`
    process.on('uncaughtException', () => { setTimeout(() => process.exit(7), 300); });
    init({ clientId: 'client-a', ingestKey: 'k', ingestUrl: process.env.INGEST });
    setTimeout(() => { throw new Error('the app decides'); }, 10);
  `);
  assert.equal(result.code, 7);
  assert.equal(received.flatMap((r) => r.body)[0]!.operation, 'uncaught_exception');
});

test('a quiet process exits on its own: the flush timer holds nothing open', async () => {
  const result = await run(`
    init({ clientId: 'client-a', ingestKey: 'k', ingestUrl: process.env.INGEST });
  `);
  assert.equal(result.code, 0);
  assert.ok(result.ms < 3000);
});
