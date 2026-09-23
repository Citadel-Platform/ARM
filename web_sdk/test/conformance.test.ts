import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { buildArmFingerprint, buildArmIssueId, sanitizeArmMap } from '../src/contract.js';

/**
 * The file `arm/tooling_core` generates and pins. This package must reproduce
 * every expected value in it; if it cannot, the browser and the Dart clients
 * disagree about what one fault is. Feature 1.6.1.
 */
interface Conformance {
  fingerprints: Array<{
    name: string;
    feature: string;
    operation: string;
    errorType: string;
    message: string;
    stack: string;
    expected: { fingerprint: string; issueId: string };
  }>;
  sanitizer: Array<{ name: string; input: Record<string, unknown>; expected: Record<string, unknown> }>;
}

const conformance = JSON.parse(
  readFileSync(new URL('../../../contract/conformance.json', import.meta.url), 'utf8'),
) as Conformance;

test('the conformance file has cases to hold to', () => {
  assert.ok(conformance.fingerprints.length >= 8);
  assert.ok(conformance.sanitizer.length >= 5);
});

for (const c of conformance.fingerprints) {
  test(`fingerprint: ${c.name}`, async () => {
    const fingerprint = buildArmFingerprint(c);
    assert.equal(fingerprint, c.expected.fingerprint);
    assert.equal(await buildArmIssueId(fingerprint), c.expected.issueId);
  });
}

for (const c of conformance.sanitizer) {
  test(`sanitizer: ${c.name}`, () => {
    assert.deepEqual(sanitizeArmMap(c.input), c.expected);
  });
}
