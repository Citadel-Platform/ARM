// Builds the installable tarball: `npm run pack:release -- <out.tgz>`.
//
// `@citadel/arm-contract` is not published anywhere, so the tarball carries
// it: the package is bundled into one ESM file with the contract inlined and
// Node's built-ins left as imports, beside the TypeScript declarations, under
// a package.json with no dependencies. `npm install <url-of-the-tgz>` then
// needs nothing but the tarball. The ARM ingest serves it at
// /sdk/v1/arm-node.tgz (cloudbuild.arm.yaml).
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = resolve(process.argv[2] ?? `${root}/arm-node.tgz`);
const stage = `${root}/dist/release`;
rmSync(stage, { recursive: true, force: true });
mkdirSync(`${stage}/dist`, { recursive: true });

await build({
  entryPoints: [`${root}/src/index.ts`],
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node18',
  outfile: `${stage}/dist/index.js`,
  logLevel: 'warning',
});
for (const name of ['index', 'arm', 'frameworks']) {
  copyFileSync(`${root}/dist/src/${name}.d.ts`, `${stage}/dist/${name}.d.ts`);
}
const manifest = JSON.parse(readFileSync(`${root}/package.json`, 'utf8'));
writeFileSync(
  `${stage}/package.json`,
  `${JSON.stringify(
    {
      name: manifest.name,
      version: manifest.version,
      description: manifest.description,
      license: manifest.license,
      type: 'module',
      main: 'dist/index.js',
      types: 'dist/index.d.ts',
      exports: { '.': { types: './dist/index.d.ts', import: './dist/index.js' } },
      engines: manifest.engines,
    },
    null,
    2,
  )}\n`,
);
cpSync(`${root}/README.md`, `${stage}/README.md`);
const packed = execFileSync('npm', ['pack', '--silent'], { cwd: stage, encoding: 'utf8' }).trim();
renameSync(`${stage}/${packed}`, out);
console.log(`${out}  ${manifest.name} ${manifest.version}`);
