// Builds ARM's browser bundles and reports their gzipped size.
//
//   dist/browser/arm.js      IIFE for a script tag. Does NOT contain Core:
//                                it reads window.CitadelCore, which the loader
//                                puts on the page first, so a page running Conduit
//                                too loads Core once.
//   dist/browser/arm.esm.js  ESM with @citadel/core-web left as an import,
//                                for bundlers, which dedupe it.
//
// ARM's own share must stay under 20 KB gzipped, Core counted once.
import { build } from 'esbuild';
import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';

const coreAsGlobal = {
  name: 'core-as-global',
  setup(b) {
    b.onResolve({ filter: /^@citadel\/core-web$/ }, () => ({ path: 'core', namespace: 'core-global' }));
    b.onLoad({ filter: /.*/, namespace: 'core-global' }, () => ({
      contents: 'module.exports = globalThis.CitadelCore || {};',
      loader: 'js',
    }));
  },
};

const common = { bundle: true, minify: true, target: ['es2019'], legalComments: 'none', logLevel: 'warning' };

await build({
  ...common,
  entryPoints: ['src/snippet.ts'],
  format: 'iife',
  outfile: 'dist/browser/arm.js',
  plugins: [coreAsGlobal],
});
await build({
  ...common,
  entryPoints: ['src/index.ts'],
  format: 'esm',
  outfile: 'dist/browser/arm.esm.js',
  external: ['@citadel/core-web'],
});

const budget = 20 * 1024;
let over = false;
for (const file of ['dist/browser/arm.js', 'dist/browser/arm.esm.js']) {
  const bytes = readFileSync(file);
  const gz = gzipSync(bytes, { level: 9 }).length;
  console.log(`${file}  ${bytes.length} B  ${gz} B gzipped`);
  if (gz > budget) over = true;
}
if (over) {
  console.error(`Over the ${budget} B gzipped budget.`);
  process.exit(1);
}
