import { getCore } from '@citadel/core-web';

import { ArmWeb, type ArmWebOptions } from './arm.js';

/**
 * The script-tag entry point. Reads its own `data-*` attributes:
 *
 *   data-client-id, data-ingest-key   required
 *   data-ingest-url                   default: the origin this script came from
 *   data-release, data-environment
 *
 * Exposes `window.citadelArm.captureException(error, options)`. Nothing here
 * throws into the page.
 */
function attribute(script: HTMLScriptElement | null, name: string): string | undefined {
  const value = script?.getAttribute(`data-${name}`)?.trim();
  return value === undefined || value === '' ? undefined : value;
}

try {
  const script = document.currentScript as HTMLScriptElement | null;
  const clientId = attribute(script, 'client-id');
  const ingestKey = attribute(script, 'ingest-key');
  let ingestUrl = attribute(script, 'ingest-url');
  if (ingestUrl === undefined && script?.src) ingestUrl = new URL(script.src).origin;
  if (clientId === undefined || ingestKey === undefined || ingestUrl === undefined) {
    console.warn('[arm] Not started: the script tag needs data-client-id and data-ingest-key.');
  } else if (typeof getCore !== 'function') {
    console.warn('[arm] Not started: the Citadel Core script did not load before ARM.');
  } else {
    const options: ArmWebOptions = { clientId, ingestKey, ingestUrl };
    const release = attribute(script, 'release');
    const environment = attribute(script, 'environment');
    if (release !== undefined) options.release = release;
    if (environment !== undefined) options.environment = environment;
    const arm = new ArmWeb(options);
    (globalThis as unknown as { citadelArm: unknown }).citadelArm = {
      captureException: (error: unknown, captureOptions?: Parameters<ArmWeb['captureException']>[1]) =>
        arm.captureException(error, captureOptions),
      flush: () => arm.flush(),
    };
  }
} catch (error) {
  try {
    console.warn('[arm] Not started:', error);
  } catch {
    // Nothing left to tell anyone with.
  }
}
