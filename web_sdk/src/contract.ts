/**
 * ARM's document contract, ported from `arm/tooling_core` (Dart), which is
 * the reference.
 *
 * Feature 1.6.1: every ARM client must produce the same fingerprint, the same
 * issue id and the same sanitised values from the same input, or one fault
 * reported from a browser and from a Dart server becomes two issues. This
 * file is held to `arm/contract/conformance.json`, which the Dart package
 * generates; a test here fails the moment the two disagree.
 *
 * It is a port, not a redesign. Where Dart's behaviour is odd — the text form
 * of a map nested too deep, a surrogate pair cut in half — it is reproduced,
 * because matching the reference is the entire job.
 */

export interface FingerprintInput {
  feature: string;
  operation: string;
  errorType: string;
  message: string;
  /** The stack exactly as the runtime gave it. */
  stack: string;
}

export function buildArmFingerprint(input: FingerprintInput): string {
  return JSON.stringify({
    feature: input.feature.trim().toLowerCase(),
    operation: input.operation.trim().toLowerCase(),
    errorType: input.errorType.trim(),
    message: normalizeMessage(input.message),
    frames: normalizeFrames(input.stack),
  });
}

/** `issue_` and the first 24 hex characters of the fingerprint's SHA-256. */
export async function buildArmIssueId(fingerprint: string): Promise<string> {
  const digest = await globalThis.crypto.subtle.digest('SHA-256', utf8(fingerprint));
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `issue_${hex.slice(0, 24)}`;
}

function normalizeMessage(value: string): string {
  const squashed = value
    .replace(/0x[0-9a-fA-F]+/g, '<hex>')
    .replace(/\b\d+\b/g, '<n>')
    .replace(/\s+/g, ' ')
    .trim();
  return squashed.length <= 240 ? squashed : squashed.slice(0, 240);
}

function normalizeFrames(stack: string): string[] {
  return stack
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '')
    .map((line) =>
      line
        .replace(/#[0-9]+\s+/g, '')
        .replace(/:\d+:\d+/g, '')
        .replace(/<asynchronous suspension>/g, '')
        .trim(),
    )
    .filter((line) => line !== '')
    .slice(0, 6);
}

/**
 * Dart's `utf8.encode`: a lone surrogate — which a 240-unit cut through an
 * emoji leaves behind — becomes U+FFFD, exactly as `TextEncoder` does.
 */
function utf8(value: string): Uint8Array<ArrayBuffer> {
  return new TextEncoder().encode(value) as Uint8Array<ArrayBuffer>;
}

export interface SanitizeLimits {
  maxDepth?: number;
  maxEntries?: number;
  maxStringLength?: number;
}

/**
 * `sanitizeArmMap`: nulls dropped at the top level only; nested maps and
 * lists keep their first `maxEntries`; strings cut at `maxStringLength`;
 * anything deeper than `maxDepth` becomes Dart's text form of it. The top
 * level is not capped at `maxEntries` — the reference does not cap it either.
 */
export function sanitizeArmMap(
  value: Record<string, unknown> | null | undefined,
  limits: SanitizeLimits = {},
): Record<string, unknown> | null {
  if (value === null || value === undefined) return null;
  const resolved = { maxDepth: 4, maxEntries: 20, maxStringLength: 2000, ...limits };
  const result: Record<string, unknown> = {};
  for (const [key, entry] of Object.entries(value)) {
    const safe = sanitizeValue(entry, 0, resolved);
    if (safe !== null && safe !== undefined) result[key] = safe;
  }
  return result;
}

function sanitizeValue(value: unknown, depth: number, limits: Required<SanitizeLimits>): unknown {
  if (depth > limits.maxDepth) {
    return value === null || value === undefined ? null : dartToString(value);
  }
  if (value === null || value === undefined || typeof value === 'number' || typeof value === 'boolean') {
    return value ?? null;
  }
  if (typeof value === 'string') {
    return value.length <= limits.maxStringLength ? value : value.slice(0, limits.maxStringLength);
  }
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) {
    return value.slice(0, limits.maxEntries).map((item) => sanitizeValue(item, depth + 1, limits));
  }
  if (typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>).slice(0, limits.maxEntries)) {
      result[key] = sanitizeValue(entry, depth + 1, limits);
    }
    return result;
  }
  return String(value);
}

/**
 * What Dart's `toString()` prints for a decoded JSON value: `{k: v}` for a
 * map, `[a, b]` for a list, `null` for null. A JavaScript number that is a
 * whole number prints without a decimal point, as a Dart `int` does; one
 * with a fraction prints as a Dart `double` would for ordinary values.
 */
function dartToString(value: unknown): string {
  if (value === null || value === undefined) return 'null';
  if (Array.isArray(value)) return `[${value.map(dartToString).join(', ')}]`;
  if (typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .map(([key, entry]) => `${key}: ${dartToString(entry)}`)
      .join(', ')}}`;
  }
  return String(value);
}
