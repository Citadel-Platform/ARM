import { GlobalRegistrator } from '@happy-dom/global-registrator';

GlobalRegistrator.register({ url: 'https://book.client.example/slots?token=secret', width: 1280, height: 800 });

import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { getCore, resetCoreForTesting } from '@citadel/core-web';

import { type ArmCapture, ArmWeb } from '../src/arm.js';

interface Batch {
  url: string;
  headers: Record<string, string>;
  captures: ArmCapture[];
}

function fakeIngest(batches: Batch[]): typeof fetch {
  return (async (url: string | URL | Request, init?: RequestInit) => {
    batches.push({
      url: String(url),
      headers: init?.headers as Record<string, string>,
      captures: JSON.parse(String(init?.body)) as ArmCapture[],
    });
    return new Response('{}', { status: 202 });
  }) as typeof fetch;
}

function start(batches: Batch[], extra: Partial<ConstructorParameters<typeof ArmWeb>[0]> = {}): ArmWeb {
  getCore({ honorDoNotTrack: false });
  return new ArmWeb({
    clientId: 'client-a',
    ingestKey: 'arm-client-a-key',
    ingestUrl: 'https://arm-ingest.example',
    release: '2.3.0',
    environment: 'production',
    fetchImpl: fakeIngest(batches),
    ...extra,
  });
}

beforeEach(() => {
  resetCoreForTesting();
  localStorage.clear();
  sessionStorage.clear();
  document.cookie = 'citadel_vid=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/';
});

test('an uncaught error is sent with the client, key, session and breadcrumbs', async () => {
  const batches: Batch[] = [];
  const arm = start(batches);
  getCore().breadcrumbs.add({ category: 'click', message: 'button#pay' });
  const error = new TypeError('cart is undefined');
  window.dispatchEvent(new ErrorEvent('error', { error, message: error.message }));
  await arm.flush();

  const batch = batches[0];
  assert.ok(batch);
  assert.equal(batch.url, 'https://arm-ingest.example/v1/captures');
  assert.equal(batch.headers['X-Citadel-Client'], 'client-a');
  assert.equal(batch.headers['X-ARM-Key'], 'arm-client-a-key');
  const capture = batch.captures[0];
  assert.ok(capture);
  assert.equal(capture.source, 'web');
  assert.equal(capture.operation, 'window_error');
  assert.equal(capture.severity, 'serious');
  assert.equal(capture.errorType, 'TypeError');
  assert.equal(capture.handled, false);
  assert.equal(capture.appVersion, '2.3.0');
  assert.equal(capture.environment, 'production');
  assert.equal(capture.sessionId, getCore().currentIdentity()?.sessionId);
  assert.equal(capture.breadcrumbs[0]?.message, 'button#pay');
  assert.equal(capture.context.url, 'https://book.client.example/slots', 'no query token');
  assert.match(capture.captureId, /^[A-Za-z0-9_-]{1,64}$/);
});

test('the wire shape is exactly what the ingest parses', async () => {
  // The Dart parser's accepted keys (arm_ingest.dart). Anything else is
  // ignored there, so a field only this side knows is a field nobody stores.
  const accepted = new Set([
    'captureId', 'occurredAt', 'source', 'severity', 'category', 'feature', 'operation',
    'message', 'errorType', 'errorName', 'stackTrace', 'sessionId', 'handled',
    'appVersion', 'buildNumber', 'releaseChannel', 'environment', 'context', 'tags',
    'errorData', 'breadcrumbs',
  ]);
  const batches: Batch[] = [];
  const arm = start(batches);
  arm.captureException(new RangeError('bad'), { feature: 'checkout', operation: 'pay' });
  await arm.flush();
  const capture = batches[0]?.captures[0] as unknown as Record<string, unknown>;
  for (const key of Object.keys(capture)) assert.ok(accepted.has(key), `the ingest does not read ${key}`);
  for (const key of ['captureId', 'occurredAt', 'feature', 'operation', 'errorType', 'sessionId']) {
    assert.ok(typeof capture[key] === 'string' && capture[key] !== '', `${key} is required`);
  }
});

test('an unhandled rejection is captured', async () => {
  const batches: Batch[] = [];
  const arm = start(batches);
  const event = new Event('unhandledrejection') as Event & { reason: unknown };
  event.reason = new Error('fetch failed');
  window.dispatchEvent(event);
  await arm.flush();
  assert.equal(batches[0]?.captures[0]?.operation, 'unhandled_rejection');
});

test('a repeat within a minute is counted and carried by the next report, not sent', async () => {
  const batches: Batch[] = [];
  const arm = start(batches);
  for (let i = 0; i < 5; i += 1) arm.captureException(new Error('same'), { operation: 'loop' });
  await arm.flush();
  assert.equal(batches.flatMap((b) => b.captures).length, 1);
});

test('a page caps what it sends: a loop that throws is one fault, not a flood', async () => {
  const batches: Batch[] = [];
  const arm = start(batches, { maxCapturesPerPage: 3 });
  for (let i = 0; i < 10; i += 1) arm.captureException(new Error(`distinct ${String.fromCharCode(97 + i)}`));
  await arm.flush();
  assert.equal(batches.flatMap((b) => b.captures).length, 3);
});

test('a server error on a watched host is captured; a 404 and SDK traffic are not', async () => {
  const batches: Batch[] = [];
  const arm = start(batches);
  const record = (status: number, host = 'api.book.client.example') => ({
    initiator: 'fetch' as const,
    method: 'GET',
    url: `https://${host}/slots`,
    host,
    path: '/slots',
    status,
    ok: false,
    durationMs: 120,
    startedAt: new Date().toISOString(),
  });
  getCore().network.emit(record(503));
  getCore().network.emit(record(404));
  getCore().network.emit(record(500, 'arm-ingest.example'));
  await arm.flush();
  const captures = batches.flatMap((b) => b.captures);
  assert.equal(captures.length, 1);
  assert.equal(captures[0]?.operation, 'http_error');
  assert.equal(captures[0]?.tags.status, 503);
});

test('a broken image is a low-severity resource failure', async () => {
  const batches: Batch[] = [];
  const arm = start(batches);
  const img = document.createElement('img');
  img.setAttribute('src', 'https://cdn.client.example/hero.jpg?v=3');
  document.body.appendChild(img);
  img.dispatchEvent(new Event('error'));
  await arm.flush();
  const capture = batches[0]?.captures[0];
  assert.equal(capture?.operation, 'resource_load');
  assert.equal(capture?.severity, 'low');
  assert.match(capture?.message ?? '', /hero\.jpg$/);
});

test('under a consent gate nothing is captured or sent', async () => {
  const batches: Batch[] = [];
  getCore({ honorDoNotTrack: false, consentMode: 'gated' });
  const arm = new ArmWeb({
    clientId: 'client-a',
    ingestKey: 'k',
    ingestUrl: 'https://arm-ingest.example',
    fetchImpl: fakeIngest(batches),
  });
  assert.equal(arm.captureException(new Error('x')), null);
  await arm.flush();
  assert.equal(batches.length, 0);
});

test('stack URLs lose their query, keep their path and position', async () => {
  const { scrubStack } = await import('../src/arm.js');
  assert.equal(
    scrubStack(
      'TypeError: x\n' +
        '    at HTMLButtonElement.onclick (https://shop.example/?utm_source=x&token=secret:8:60)\n' +
        '    at pay (https://shop.example/app.js?v=3#h:12:4)\n' +
        'render@https://shop.example/reset?token=abc:3:1\n' +
        '    at https://shop.example/plain.js:1:2',
    ),
    'TypeError: x\n' +
      '    at HTMLButtonElement.onclick (https://shop.example/:8:60)\n' +
      '    at pay (https://shop.example/app.js:12:4)\n' +
      'render@https://shop.example/reset:3:1\n' +
      '    at https://shop.example/plain.js:1:2',
  );
});
