import { randomUUID } from 'node:crypto';
import { hostname } from 'node:os';

import { buildArmFingerprint, sanitizeArmMap } from '@citadel/arm-contract';

/**
 * ARM for a Node server.
 *
 * Captures what goes wrong in a server process and sends it to Citadel's
 * shared ARM ingest, which groups it and writes it into the client's own
 * `citadel-arm`. It never writes Firestore, and it holds no credential but
 * the client id and the public ARM ingest key.
 *
 * **It must never hurt the host.** Every entry point is wrapped so a fault in
 * here is swallowed, sending happens off the request path, the flush timer
 * does not keep the process alive, and an unreachable ingest costs one
 * bounded request per batch, never a blocked handler.
 */

export const armNodeVersion = '0.1.0';

export type ArmSeverity = 'info' | 'low' | 'moderate' | 'serious' | 'critical';

export interface ArmNodeOptions {
  /** The client's Citadel project id. */
  clientId: string;
  /** From ARM → Set up ARM → Issue the ingest key. */
  ingestKey: string;
  /** The ARM ingest's address. */
  ingestUrl: string;
  release?: string;
  environment?: string;
  /** What this process is — `api`, `worker`. Recorded on every capture. */
  service?: string;
  /**
   * The application's root. Stack paths under it are sent relative to it, so
   * a deploy into a new directory does not make every fault a new issue, and
   * no server path leaves the machine. Default `process.cwd()`.
   */
  root?: string;
  /** Capture uncaught exceptions and unhandled rejections. Default true. */
  captureUncaught?: boolean;
  /** Most captures sent per minute; the rest are counted, not sent. Default 60. */
  maxCapturesPerMinute?: number;
  /** How long a fatal exception waits for its capture to send. Default 2000 ms. */
  fatalFlushTimeoutMs?: number;
  /** Tests only. */
  fetchImpl?: typeof fetch;
  /** Tests only: do not touch the process's handlers. */
  installProcessHandlers?: boolean;
}

export interface CaptureOptions {
  feature?: string;
  operation?: string;
  severity?: ArmSeverity;
  category?: string;
  handled?: boolean;
  tags?: Record<string, unknown>;
  /** What the request was. Method, route and status — never a body or header. */
  request?: RequestContext;
}

export interface RequestContext {
  method?: string;
  /** The route pattern (`/orders/:id`) when the framework knows it. */
  route?: string;
  /** The path, without its query string. */
  path?: string;
  status?: number;
  durationMs?: number;
}

export interface ArmCapture {
  captureId: string;
  occurredAt: string;
  source: 'node';
  severity: ArmSeverity;
  category: string;
  feature: string;
  operation: string;
  message: string;
  errorType: string;
  errorName?: string;
  stackTrace: string;
  sessionId: string;
  handled: boolean;
  appVersion?: string;
  environment?: string;
  context: Record<string, unknown>;
  tags: Record<string, unknown>;
  breadcrumbs: never[];
}

const duplicateWindowMs = 60_000;
const maxBatch = 20;
const maxQueue = 100;
const flushIntervalMs = 5_000;
const requestTimeoutMs = 5_000;

export class ArmNode {
  readonly options: ArmNodeOptions;
  /** One per process: a server has no visitor session, and the ingest wants an id. */
  readonly processId = `proc-${randomUUID()}`;
  private readonly root: string;
  private readonly queue: ArmCapture[] = [];
  private readonly seen = new Map<string, { at: number; suppressed: number }>();
  private minuteStart = 0;
  private sentThisMinute = 0;
  private timer: ReturnType<typeof setInterval> | null = null;
  private inflight: Promise<void> | null = null;
  private capturing = false;
  private closed = false;
  private readonly removers: Array<() => void> = [];

  constructor(options: ArmNodeOptions) {
    this.options = options;
    this.root = normalizeRoot(options.root ?? safeCwd());
    this.timer = setInterval(() => void this.flush(), flushIntervalMs);
    this.timer.unref?.();
    if (options.captureUncaught !== false && options.installProcessHandlers !== false) {
      this.installProcessHandlers();
    }
  }

  /**
   * Reports an error the application caught. Returns the capture id, or null
   * when it was not sent: a repeat inside the minute, the per-minute cap, or
   * this client failing — which it does silently.
   */
  captureException(error: unknown, options: CaptureOptions = {}): string | null {
    return this.capture(error, {
      feature: options.feature ?? this.options.service ?? 'server',
      operation: options.operation ?? 'captured',
      severity: options.severity ?? 'moderate',
      category: options.category ?? 'exception',
      handled: options.handled ?? true,
      tags: options.tags ?? {},
      ...(options.request === undefined ? {} : { request: options.request }),
    });
  }

  /** Sends what is queued. Never rejects. */
  flush(): Promise<void> {
    if (this.inflight !== null) return this.inflight;
    if (this.queue.length === 0) return Promise.resolve();
    const batch = this.queue.splice(0, maxBatch);
    this.inflight = this.send(batch)
      .catch(() => undefined)
      .finally(() => {
        this.inflight = null;
      });
    return this.inflight.then(() => (this.queue.length > 0 ? this.flush() : undefined));
  }

  /** Flushes, stops the timer and removes the process handlers. */
  async close(timeoutMs = 2000): Promise<void> {
    this.closed = true;
    if (this.timer !== null) clearInterval(this.timer);
    this.timer = null;
    for (const remove of this.removers.splice(0)) remove();
    await withTimeout(this.flush(), timeoutMs);
  }

  /** The stack as it will be sent: paths under the root made relative. Exposed for tests. */
  relativeStack(stack: string): string {
    if (this.root === '') return stack;
    return stack.split(this.root).join('').replace(/file:\/\/(?=[^/])/g, '');
  }

  // ---------------------------------------------------------------- capture

  capture(
    error: unknown,
    input: {
      feature: string;
      operation: string;
      severity: ArmSeverity;
      category: string;
      handled: boolean;
      tags: Record<string, unknown>;
      request?: RequestContext;
    },
  ): string | null {
    if (this.capturing || this.closed) return null;
    this.capturing = true;
    try {
      const parts = describe(error);
      const stack = this.relativeStack(parts.stack);
      const now = Date.now();

      const key = buildArmFingerprint({
        feature: input.feature,
        operation: input.operation,
        errorType: parts.type,
        message: parts.message,
        stack,
      });
      const previous = this.seen.get(key);
      if (previous !== undefined && now - previous.at < duplicateWindowMs) {
        previous.suppressed += 1;
        return null;
      }
      if (now - this.minuteStart >= 60_000) {
        this.minuteStart = now;
        this.sentThisMinute = 0;
      }
      if (this.sentThisMinute >= (this.options.maxCapturesPerMinute ?? 60)) return null;
      this.sentThisMinute += 1;
      const suppressed = previous?.suppressed ?? 0;
      this.seen.set(key, { at: now, suppressed: 0 });
      if (this.seen.size > 500) this.seen.delete(this.seen.keys().next().value as string);

      const context: Record<string, unknown> = {
        runtime: `node ${process.version}`,
        platform: process.platform,
        host: safeHostname(),
        pid: process.pid,
      };
      if (this.options.service !== undefined) context.service = this.options.service;
      if (input.request !== undefined) context.request = cleanRequest(input.request);

      const capture: ArmCapture = {
        captureId: randomUUID(),
        occurredAt: new Date(now).toISOString(),
        source: 'node',
        severity: input.severity,
        category: input.category,
        feature: input.feature,
        operation: input.operation,
        message: parts.message,
        errorType: parts.type,
        stackTrace: stack,
        sessionId: this.processId,
        handled: input.handled,
        context: sanitizeArmMap(context) ?? {},
        tags:
          sanitizeArmMap({
            ...input.tags,
            ...(suppressed > 0 ? { suppressedSinceLastReport: suppressed } : {}),
          }) ?? {},
        breadcrumbs: [],
      };
      if (parts.name !== undefined) capture.errorName = parts.name;
      if (this.options.release !== undefined) capture.appVersion = this.options.release;
      if (this.options.environment !== undefined) capture.environment = this.options.environment;

      if (this.queue.length >= maxQueue) this.queue.shift();
      this.queue.push(capture);
      if (this.queue.length >= maxBatch) void this.flush();
      return capture.captureId;
    } catch {
      return null;
    } finally {
      this.capturing = false;
    }
  }

  // ------------------------------------------------------------- transport

  private async send(batch: ArmCapture[]): Promise<void> {
    const url = `${this.options.ingestUrl.replace(/\/+$/, '')}/v1/captures`;
    const body = JSON.stringify(batch);
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
      timeout.unref?.();
      try {
        const response = await (this.options.fetchImpl ?? fetch)(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'X-Citadel-Client': this.options.clientId,
            'X-ARM-Key': this.options.ingestKey,
            'User-Agent': `citadel-arm-node/${armNodeVersion}`,
          },
          body,
          signal: controller.signal,
        });
        // 4xx other than 429 will not get better by asking again: a wrong key,
        // a data plane not built yet. Drop rather than loop.
        if (response.ok || (response.status < 500 && response.status !== 429)) return;
      } catch {
        // Unreachable or timed out: retried below.
      } finally {
        clearTimeout(timeout);
      }
      if (attempt < 2) await sleep(250 * 2 ** attempt + Math.random() * 250);
    }
  }

  // --------------------------------------------------------------- process

  /**
   * Node's own behaviour on an uncaught exception is to print it and exit 1,
   * and a monitoring client must not change that. So:
   *
   * - When nothing else handles `uncaughtException`, ARM does: it captures,
   *   waits up to `fatalFlushTimeoutMs` for the capture to leave, prints the
   *   error as Node would, and exits 1. An unhandled rejection reaches the
   *   same place — Node turns it into an uncaught exception unless something
   *   listens for `unhandledRejection`, and ARM deliberately does not.
   * - When the application has its own handler, the application decides what
   *   happens next. ARM only watches (`uncaughtExceptionMonitor`) and sends
   *   what it can.
   */
  private installProcessHandlers(): void {
    const ownsFatal = process.listenerCount('uncaughtException') === 0;
    const record = (error: unknown, origin: string): void => {
      this.capture(error, {
        feature: this.options.service ?? 'server',
        operation: origin === 'unhandledRejection' ? 'unhandled_rejection' : 'uncaught_exception',
        severity: 'critical',
        category: 'runtime',
        handled: false,
        tags: {},
      });
    };
    if (ownsFatal) {
      const onFatal = (error: unknown, origin: string): void => {
        record(error, origin);
        void withTimeout(this.flush(), this.options.fatalFlushTimeoutMs ?? 2000).finally(() => {
          try {
            process.stderr.write(`${error instanceof Error && error.stack ? error.stack : String(error)}\n`);
          } finally {
            process.exit(1);
          }
        });
      };
      process.on('uncaughtException', onFatal);
      this.removers.push(() => process.off('uncaughtException', onFatal));
    } else {
      const onMonitor = (error: unknown, origin: string): void => {
        record(error, origin);
        void this.flush();
      };
      process.on('uncaughtExceptionMonitor', onMonitor);
      this.removers.push(() => process.off('uncaughtExceptionMonitor', onMonitor));
    }
  }
}

function cleanRequest(request: RequestContext): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (request.method !== undefined) out.method = request.method.toUpperCase();
  if (request.route !== undefined) out.route = request.route;
  // The query string can carry a token or an email address; it never leaves.
  if (request.path !== undefined) out.path = request.path.split('?')[0]!.split('#')[0];
  if (request.status !== undefined) out.status = request.status;
  if (request.durationMs !== undefined) out.durationMs = Math.round(request.durationMs);
  return out;
}

function normalizeRoot(root: string): string {
  const trimmed = root.replace(/[\\/]+$/, '');
  return trimmed === '' ? '' : `${trimmed}/`;
}

function safeCwd(): string {
  try {
    return process.cwd();
  } catch {
    return '';
  }
}

function safeHostname(): string {
  try {
    return hostname();
  } catch {
    return '';
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    timer.unref?.();
  });
}

function withTimeout(work: Promise<void>, ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    timer.unref?.();
    work.then(
      () => {
        clearTimeout(timer);
        resolve();
      },
      () => {
        clearTimeout(timer);
        resolve();
      },
    );
  });
}

/** What an unknown thrown value says about itself. Same rules as `arm-web`. */
export function describe(error: unknown): { message: string; type: string; name?: string; stack: string } {
  if (error instanceof Error) {
    const type = error.constructor?.name && error.constructor.name !== 'Object' ? error.constructor.name : 'Error';
    const parts: { message: string; type: string; name?: string; stack: string } = {
      message: error.message,
      type,
      stack: typeof error.stack === 'string' ? error.stack : '',
    };
    if (error.name && error.name !== type) parts.name = error.name;
    return parts;
  }
  if (typeof error === 'string') return { message: error, type: 'Error', stack: '' };
  let message: string;
  try {
    message = JSON.stringify(error) ?? String(error);
  } catch {
    message = String(error);
  }
  return { message: message.slice(0, 1000), type: typeof error === 'object' && error !== null ? 'Object' : typeof error, stack: '' };
}
