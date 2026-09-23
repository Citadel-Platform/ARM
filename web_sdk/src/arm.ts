import {
  type CitadelCore,
  getCore,
  joinUrl,
  type NetworkRecord,
  randomId,
  sanitizeUrl,
  type Transport,
} from '@citadel/core-web';

import { buildArmFingerprint } from './contract.js';

/**
 * ARM for the browser.
 *
 * Captures what goes wrong on a page and sends it to Citadel's shared ARM
 * ingest, which groups it and writes it into the client's own `citadel-arm`.
 * Everything shared with other products — session, consent, breadcrumbs, the
 * network observer, transport — is the Citadel Core SDK's; this file owns only
 * what an error is and what is sent about it.
 *
 * The ingest computes the fingerprint (decided 23/09/26), so this sends what it
 * saw. The contract port in `contract.ts` is used only to recognise a repeat
 * on this page before sending it — the Flutter SDK's suppression, same window.
 */

export const armWebVersion = '0.1.0';

export type ArmSeverity = 'info' | 'low' | 'moderate' | 'serious' | 'critical';

export interface ArmWebOptions {
  /** The client's Citadel project id. */
  clientId: string;
  /** From ARM → Set up ARM → Issue the ingest key. */
  ingestKey: string;
  /** The ARM ingest's address. */
  ingestUrl: string;
  release?: string;
  environment?: string;
  /** Capture uncaught errors, rejections, failed requests and resources. Default true. */
  autocapture?: boolean;
  /** Most captures one page load sends. Default 30: a loop that throws is one fault. */
  maxCapturesPerPage?: number;
  fetchImpl?: typeof fetch;
}

export interface CaptureOptions {
  feature?: string;
  operation?: string;
  severity?: ArmSeverity;
  category?: string;
  handled?: boolean;
  tags?: Record<string, unknown>;
}

export interface ArmCapture {
  captureId: string;
  occurredAt: string;
  source: 'web';
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
  breadcrumbs: ReturnType<CitadelCore['breadcrumbs']['snapshot']>;
}

/** A repeat of one fingerprint inside this window is counted, not sent (Flutter's rule). */
const duplicateWindowMs = 60_000;

export class ArmWeb {
  private readonly core: CitadelCore;
  private readonly options: ArmWebOptions;
  private readonly transport: Transport<ArmCapture>;
  private readonly seen = new Map<string, { at: number; suppressed: number }>();
  private sentThisPage = 0;
  private capturing = false;

  constructor(options: ArmWebOptions) {
    this.options = options;
    const coreOptions: Parameters<typeof getCore>[0] = {};
    if (options.release !== undefined) coreOptions.release = options.release;
    if (options.environment !== undefined) coreOptions.environment = options.environment;
    this.core = getCore(coreOptions);
    this.core.registerProduct('arm', armWebVersion);
    const url = joinUrl(options.ingestUrl, 'v1/captures');
    this.transport = this.core.createTransport<ArmCapture>({
      name: 'arm',
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Citadel-Client': options.clientId,
        'X-ARM-Key': options.ingestKey,
      },
      beaconUrl:
        `${url}?client=${encodeURIComponent(options.clientId)}` +
        `&key=${encodeURIComponent(options.ingestKey)}`,
      // The ingest takes at most 20 per batch.
      maxBatchSize: 20,
      flushIntervalMs: 3000,
      ...(options.fetchImpl === undefined ? {} : { fetchImpl: options.fetchImpl }),
    });
    if (options.autocapture !== false) this.install();
  }

  /**
   * Reports an error the page caught. Returns the capture id, or null when it
   * was not sent: collection not allowed, a repeat inside the minute, or the
   * page's cap reached.
   */
  captureException(error: unknown, options: CaptureOptions = {}): string | null {
    const parts = describe(error);
    return this.capture({
      message: parts.message,
      errorType: parts.type,
      ...(parts.name === undefined ? {} : { errorName: parts.name }),
      stackTrace: parts.stack,
      feature: options.feature ?? 'web',
      operation: options.operation ?? 'captured',
      severity: options.severity ?? 'low',
      category: options.category ?? 'exception',
      handled: options.handled ?? true,
      tags: options.tags ?? {},
    });
  }

  flush(): Promise<void> {
    return this.transport.flush();
  }

  // ---------------------------------------------------------------- capture

  private capture(input: {
    message: string;
    errorType: string;
    errorName?: string;
    stackTrace: string;
    feature: string;
    operation: string;
    severity: ArmSeverity;
    category: string;
    handled: boolean;
    tags: Record<string, unknown>;
  }): string | null {
    // An error thrown while reporting an error must not report itself.
    if (this.capturing) return null;
    this.capturing = true;
    try {
      const identity = this.core.currentIdentity();
      if (identity === null) return null;
      if (this.sentThisPage >= (this.options.maxCapturesPerPage ?? 30)) return null;

      const key = buildArmFingerprint({
        feature: input.feature,
        operation: input.operation,
        errorType: input.errorType,
        message: input.message,
        stack: input.stackTrace,
      });
      const now = Date.now();
      const previous = this.seen.get(key);
      if (previous !== undefined && now - previous.at < duplicateWindowMs) {
        previous.suppressed += 1;
        return null;
      }
      const suppressed = previous?.suppressed ?? 0;
      this.seen.set(key, { at: now, suppressed: 0 });
      this.sentThisPage += 1;

      const release = this.core.releaseIdentity();
      const device = this.core.device();
      const capture: ArmCapture = {
        captureId: randomId(),
        occurredAt: new Date(now).toISOString(),
        source: 'web',
        severity: input.severity,
        category: input.category,
        feature: input.feature,
        operation: input.operation,
        message: scrubStack(input.message),
        errorType: input.errorType,
        stackTrace: scrubStack(input.stackTrace),
        sessionId: identity.sessionId,
        handled: input.handled,
        context: {
          url: sanitizeUrl(globalThis.location?.href ?? ''),
          device,
          ...(document.visibilityState === undefined ? {} : { visibility: document.visibilityState }),
        },
        tags: {
          ...input.tags,
          // Only when there were any, as the Flutter SDK does.
          ...(suppressed > 0 ? { suppressedSinceLastReport: suppressed } : {}),
        },
        breadcrumbs: this.core.breadcrumbs.snapshot(),
      };
      if (input.errorName !== undefined) capture.errorName = input.errorName;
      if (release.release !== null) capture.appVersion = release.release;
      if (release.environment !== null) capture.environment = release.environment;
      this.transport.enqueue(capture);
      return capture.captureId;
    } catch {
      return null;
    } finally {
      this.capturing = false;
    }
  }

  // ------------------------------------------------------------ autocapture

  private install(): void {
    const win = globalThis as unknown as Window;
    if (typeof win.addEventListener !== 'function') return;

    win.addEventListener(
      'error',
      (event: Event) => {
        const target = event.target;
        if (target !== null && target !== win && target instanceof Element) {
          this.onResourceError(target);
          return;
        }
        const errorEvent = event as ErrorEvent;
        const parts = describe(errorEvent.error ?? errorEvent.message);
        // "Script error." with no stack is a cross-origin script the browser
        // will not describe. It is recorded, but as what it is.
        this.capture({
          message: parts.message || String(errorEvent.message ?? 'Script error.'),
          errorType: parts.type,
          ...(parts.name === undefined ? {} : { errorName: parts.name }),
          stackTrace:
            parts.stack ||
            (errorEvent.filename
              ? `at ${sanitizeUrl(errorEvent.filename)}:${errorEvent.lineno ?? 0}:${errorEvent.colno ?? 0}`
              : ''),
          feature: 'web',
          operation: 'window_error',
          severity: 'serious',
          category: 'runtime',
          handled: false,
          tags: {},
        });
      },
      { capture: true },
    );

    win.addEventListener('unhandledrejection', (event: Event) => {
      const parts = describe((event as PromiseRejectionEvent).reason);
      this.capture({
        message: parts.message,
        errorType: parts.type,
        ...(parts.name === undefined ? {} : { errorName: parts.name }),
        stackTrace: parts.stack,
        feature: 'web',
        operation: 'unhandled_rejection',
        severity: 'serious',
        category: 'runtime',
        handled: false,
        tags: {},
      });
    });

    win.document?.addEventListener('securitypolicyviolation', (event: Event) => {
      const violation = event as SecurityPolicyViolationEvent;
      this.capture({
        message: `${violation.effectiveDirective} blocked ${sanitizeUrl(violation.blockedURI) || violation.blockedURI}`,
        errorType: 'SecurityPolicyViolation',
        stackTrace: violation.sourceFile ? `at ${sanitizeUrl(violation.sourceFile)}:${violation.lineNumber}:${violation.columnNumber}` : '',
        feature: 'web',
        operation: 'csp_violation',
        severity: 'low',
        category: 'security',
        handled: false,
        tags: { directive: violation.effectiveDirective, disposition: violation.disposition },
      });
    });

    this.core.network.subscribe((record) => this.onRequest(record));
  }

  private onResourceError(target: Element): void {
    const tag = target.tagName.toLowerCase();
    const raw = target.getAttribute('src') ?? target.getAttribute('href') ?? '';
    const url = raw === '' ? '' : sanitizeUrl(raw);
    this.capture({
      message: `${tag} failed to load ${url}`.trim(),
      errorType: 'ResourceLoadError',
      stackTrace: '',
      feature: 'web',
      operation: 'resource_load',
      severity: 'low',
      category: 'resource',
      handled: false,
      tags: { element: tag },
    });
  }

  /**
   * A failed request to a host the client watches. 5xx is the server
   * failing; status 0 is the request never completing, which is also what a
   * visitor navigating away mid-request looks like, so it is kept low. 4xx is
   * usually the page asking wrongly and is left to Conduit's API errors.
   */
  private onRequest(record: NetworkRecord): void {
    if (!this.core.watchesHost(record.host)) return;
    if (record.status !== 0 && record.status < 500) return;
    if (record.error === 'aborted') return;
    this.capture({
      message:
        record.status === 0
          ? `${record.method} ${record.url} did not complete`
          : `${record.method} ${record.url} answered ${record.status}`,
      errorType: record.status === 0 ? 'NetworkError' : 'HttpError',
      stackTrace: '',
      feature: 'web',
      operation: 'http_error',
      severity: record.status === 0 ? 'low' : 'moderate',
      category: 'network',
      handled: false,
      tags: {
        method: record.method,
        host: record.host,
        path: record.path,
        status: record.status,
        durationMs: record.durationMs,
      },
    });
  }
}

/**
 * A stack with every URL's query string and fragment removed.
 *
 * A frame in an inline script names the page it ran on, query and all — seen
 * live, 23/09/26: a reset token in the address arrived in the client's
 * database inside a stack trace. The query goes; the path and the
 * `:line:column` after it stay, because those are what a stack is for.
 */
export function scrubStack(stack: string): string {
  return stack.replace(
    /(\b(?:https?|file):\/\/[^\s?#()]+)[?#][^\s()]*?(:\d+:\d+|:\d+)?(?=[\s)]|$)/g,
    (_match, base: string, position: string | undefined) => `${base}${position ?? ''}`,
  );
}

/** What an unknown thrown value says about itself. */
function describe(error: unknown): { message: string; type: string; name?: string; stack: string } {
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
