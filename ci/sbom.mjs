#!/usr/bin/env node
// Software bill of materials + dependency audit for the built release (npm's own tooling, lockfile only).
//   node ci/sbom.mjs <work-dir>
// Writes <work-dir>/sbom.cdx.json (CycloneDX) and ci/out/deps.json. Gate: no high or critical advisories.
// Advisory details stay internal (ci/out/deps.json); the public run record only shows whether the gate passed.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const work = resolve(process.argv[2] || join(repo, 'ci', 'out', 'work'));
const buildRoot = join(repo, 'portal', 'build');
const app = existsSync(buildRoot) ? readdirSync(buildRoot).filter((d) => /^mrpearson-v\d+\.\d+\.\d+$/.test(d)).sort().pop() : null;
if (!app) { console.error('no built release in portal/build (run the build stage first)'); console.log('0 passed, 1 failed'); process.exit(1); }
const cwd = join(buildRoot, app);
const npm = (...a) => spawnSync(process.platform === 'win32' ? 'npm.cmd' : 'npm', a, { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, shell: process.platform === 'win32' });
mkdirSync(work, { recursive: true });

let passed = 0; let failed = 0;
const deps = { release: app, components: null, audit: null };

const s = npm('sbom', '--sbom-format', 'cyclonedx', '--package-lock-only', '--omit', 'dev');
try {
  const bom = JSON.parse(s.stdout);
  if (bom.bomFormat !== 'CycloneDX' || !Array.isArray(bom.components)) throw new Error('not a CycloneDX document');
  writeFileSync(join(work, 'sbom.cdx.json'), s.stdout);
  deps.components = bom.components.length;
  console.log(`SBOM: CycloneDX ${bom.specVersion}, ${bom.components.length} components -> ${join(work, 'sbom.cdx.json')}`);
  passed += 1;
} catch (err) { console.log(`SBOM failed: ${err.message} ${String(s.stderr || '').slice(0, 300)}`); failed += 1; }

const a = npm('audit', '--package-lock-only', '--omit', 'dev', '--json');
try {
  const v = JSON.parse(a.stdout).metadata.vulnerabilities;
  const blocking = (v.high || 0) + (v.critical || 0);
  deps.audit = { gate: blocking ? 'failed' : 'passed', counts: { info: v.info || 0, low: v.low || 0, moderate: v.moderate || 0, high: v.high || 0, critical: v.critical || 0 } };
  console.log(`audit: critical ${v.critical || 0}, high ${v.high || 0}, moderate ${v.moderate || 0}, low ${v.low || 0} -> gate ${deps.audit.gate}`);
  if (blocking) failed += 1; else passed += 1;
} catch (err) { console.log(`audit unavailable (${err.message}); the registry must be reachable`); failed += 1; }

mkdirSync(join(repo, 'ci', 'out'), { recursive: true });
writeFileSync(join(repo, 'ci', 'out', 'deps.json'), JSON.stringify(deps, null, 2) + '\n');
console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
