import type { ArmNode, RequestContext } from './arm.js';

/**
 * The framework hooks. Each is written against the smallest shape it needs,
 * not the framework's own types, so this package depends on none of them and
 * a version bump in one cannot break the others.
 *
 * What a request contributes to a capture: method, route pattern, path
 * without its query, status and duration. Never a header, a cookie or a body.
 */

export interface RequestHookOptions {
  /** A response slower than this is reported as a slow request. Default 3000 ms; 0 turns it off. */
  slowMs?: number;
}

const captured = Symbol.for('citadel.arm.captured');

/**
 * The error types a request's outcome is reported under — the same names
 * `arm-web` and `arm-php` use, so a 5xx is one kind of thing in the Console
 * whichever runtime saw it. Classes rather than a renamed `Error`, because the
 * type is read from the constructor.
 */
class HttpError extends Error {}
class SlowRequest extends Error {}

interface NodeRequest {
  method?: string;
  url?: string;
  originalUrl?: string;
  baseUrl?: string;
  route?: { path?: unknown };
  [captured]?: boolean;
}

interface NodeResponse {
  statusCode: number;
  once(event: 'finish', listener: () => void): unknown;
}

function pathOf(url: string | undefined): string | undefined {
  return url === undefined ? undefined : url.split('?')[0]!.split('#')[0];
}

function expressRoute(req: NodeRequest): string | undefined {
  const path = req.route?.path;
  return typeof path === 'string' ? `${req.baseUrl ?? ''}${path}` : undefined;
}

function reportResponse(
  arm: ArmNode,
  request: RequestContext,
  alreadyCaptured: boolean,
  slowMs: number,
): void {
  const where = request.route ?? request.path ?? '';
  if ((request.status ?? 0) >= 500 && !alreadyCaptured) {
    const error = new HttpError(`${request.method ?? ''} ${where} answered ${request.status}`.trim());
    error.stack = '';
    arm.capture(error, {
      feature: arm.options.service ?? 'server',
      operation: 'http_5xx',
      severity: 'serious',
      category: 'network',
      handled: false,
      tags: { status: request.status },
      request,
    });
  }
  if (slowMs > 0 && (request.durationMs ?? 0) > slowMs) {
    const error = new SlowRequest(`${request.method ?? ''} ${where} took longer than ${slowMs} ms`.trim());
    error.stack = '';
    arm.capture(error, {
      feature: arm.options.service ?? 'server',
      operation: 'slow_request',
      severity: 'low',
      category: 'performance',
      handled: true,
      tags: { thresholdMs: slowMs },
      request,
    });
  }
}

/**
 * Connect-style middleware — Express, Connect, and anything with
 * `(req, res, next)`. Mount it first: it reports 5xx answers and slow ones,
 * whatever produced them.
 */
export function armRequestHandler(arm: ArmNode, options: RequestHookOptions = {}) {
  const slowMs = options.slowMs ?? 3000;
  return (req: NodeRequest, res: NodeResponse, next: (error?: unknown) => void): void => {
    try {
      const started = performance.now();
      res.once('finish', () => {
        try {
          const request: RequestContext = {
            status: res.statusCode,
            durationMs: performance.now() - started,
          };
          if (req.method !== undefined) request.method = req.method;
          const route = expressRoute(req);
          if (route !== undefined) request.route = route;
          const path = pathOf(req.originalUrl ?? req.url);
          if (path !== undefined) request.path = path;
          reportResponse(arm, request, req[captured] === true, slowMs);
        } catch {
          // Never into the host.
        }
      });
    } catch {
      // Never into the host.
    }
    next();
  };
}

/**
 * Express error middleware. Mount it after the routes and before the
 * application's own error handler: it records the error with its request and
 * passes it on unchanged.
 */
export function armErrorHandler(arm: ArmNode) {
  // Four parameters: Express recognises an error handler by its arity.
  return (error: unknown, req: NodeRequest, _res: unknown, next: (error?: unknown) => void): void => {
    try {
      const request: RequestContext = {};
      if (req.method !== undefined) request.method = req.method;
      const route = expressRoute(req);
      if (route !== undefined) request.route = route;
      const path = pathOf(req.originalUrl ?? req.url);
      if (path !== undefined) request.path = path;
      arm.capture(error, {
        feature: arm.options.service ?? 'server',
        operation: 'request_error',
        severity: 'serious',
        category: 'exception',
        handled: false,
        tags: {},
        request,
      });
      req[captured] = true;
    } catch {
      // Never into the host.
    }
    next(error);
  };
}

interface FastifyRequestLike {
  method: string;
  url: string;
  routeOptions?: { url?: string };
  [captured]?: boolean;
}
interface FastifyReplyLike {
  statusCode: number;
  elapsedTime?: number;
}
interface FastifyLike {
  addHook(name: 'onError', hook: (request: FastifyRequestLike, reply: FastifyReplyLike, error: unknown) => Promise<void>): unknown;
  addHook(name: 'onResponse', hook: (request: FastifyRequestLike, reply: FastifyReplyLike) => Promise<void>): unknown;
}

/**
 * A Fastify plugin: `fastify.register(armFastify(arm))`. Marked to skip
 * Fastify's encapsulation — what `fastify-plugin` does — so its hooks see
 * every route, not only those registered inside it.
 */
export function armFastify(arm: ArmNode, options: RequestHookOptions = {}) {
  const slowMs = options.slowMs ?? 3000;
  const request = (req: FastifyRequestLike, reply?: FastifyReplyLike): RequestContext => {
    const context: RequestContext = { method: req.method };
    const route = req.routeOptions?.url;
    if (route !== undefined) context.route = route;
    const path = pathOf(req.url);
    if (path !== undefined) context.path = path;
    if (reply !== undefined) {
      context.status = reply.statusCode;
      if (reply.elapsedTime !== undefined) context.durationMs = reply.elapsedTime;
    }
    return context;
  };
  const plugin = async (fastify: FastifyLike): Promise<void> => {
    fastify.addHook('onError', async (req, _reply, error) => {
      try {
        arm.capture(error, {
          feature: arm.options.service ?? 'server',
          operation: 'request_error',
          severity: 'serious',
          category: 'exception',
          handled: false,
          tags: {},
          request: request(req),
        });
        req[captured] = true;
      } catch {
        // Never into the host.
      }
    });
    fastify.addHook('onResponse', async (req, reply) => {
      try {
        reportResponse(arm, request(req, reply), req[captured] === true, slowMs);
      } catch {
        // Never into the host.
      }
    });
  };
  (plugin as unknown as Record<symbol, boolean>)[Symbol.for('skip-override')] = true;
  return plugin;
}

interface NextRequestInfo {
  path?: string;
  method?: string;
}
interface NextErrorContext {
  routePath?: string;
  routeType?: string;
  routerKind?: string;
}

/**
 * Next.js's `onRequestError`, exported from `instrumentation.ts`:
 *
 *   export const onRequestError = armNextOnRequestError(arm);
 *
 * Called by Next for errors in server components, route handlers, server
 * actions and middleware, with the route that failed.
 */
export function armNextOnRequestError(arm: ArmNode) {
  return async (error: unknown, request: NextRequestInfo, context: NextErrorContext): Promise<void> => {
    try {
      const info: RequestContext = {};
      if (request?.method !== undefined) info.method = request.method;
      if (context?.routePath !== undefined) info.route = context.routePath;
      const path = pathOf(request?.path);
      if (path !== undefined) info.path = path;
      arm.capture(error, {
        feature: arm.options.service ?? 'next',
        operation: context?.routeType ? `${context.routeType}_error` : 'request_error',
        severity: 'serious',
        category: 'exception',
        handled: false,
        tags: context?.routerKind ? { routerKind: context.routerKind } : {},
        request: info,
      });
      await arm.flush();
    } catch {
      // Never into the host.
    }
  };
}
