import { ArmWeb, type ArmWebOptions } from './arm.js';

export { type ArmCapture, type ArmSeverity, ArmWeb, type ArmWebOptions, armWebVersion, type CaptureOptions, scrubStack } from './arm.js';
export { buildArmFingerprint, buildArmIssueId, type FingerprintInput, sanitizeArmMap, type SanitizeLimits } from './contract.js';

/** Starts ARM on this page and returns it. */
export function init(options: ArmWebOptions): ArmWeb {
  return new ArmWeb(options);
}
