// Release pipeline: public wording for /engineering. ci/stages.mjs adds the command for each stage id, so the page
// can only describe stages that actually run. Run records come from ci/run.mjs (allow-listed fields only).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const stages = [
  { id: 'facts', name: 'Facts & claims', what: 'Prices, service levels, CMMC dates and NAICS codes are cross-checked against the source documents. Banned or unprovable claims, broken links, weak contrast, page weight and the content security policy are checked too.', controls: ['3.4.4'] },
  { id: 'build', name: 'Build from source', what: 'Every change is applied as an exact, counted patch to the recorded application source. Any drift stops the build.', controls: ['3.4.1', '3.4.3'] },
  { id: 'static', name: 'Release integrity', what: 'Only intended files changed, file encodings are preserved, retired features are fully gone, and no secrets or internal details ship.', controls: ['3.4.1', '3.4.2'] },
  { id: 'smoke', name: 'Live application test', what: 'The built application runs in production mode and is driven end to end: public site, forms, client portal, every admin page, data retention and rate limits.', controls: ['3.4.4'] },
  { id: 'secrets', name: 'Secret scan', what: 'The whole repository is scanned for credentials and private keys.', controls: ['3.4.2'] },
  { id: 'deps', name: 'Dependencies & SBOM', what: 'A CycloneDX software bill of materials is generated from the lockfile, and the release is blocked on any high or critical advisory.', controls: ['3.4.1', '3.14.1'] },
  { id: 'rehearsal', name: 'Deploy rehearsal', what: 'The real deploy, rollback, web-server and backup scripts run against a production look-alike (Ubuntu 24.04, nginx 1.24, Node 24), including injected failures that must roll back on their own.', controls: ['3.4.4', '3.4.5'] },
];

// NIST SP 800-171 Rev. 2 requirement text, verbatim (the website tests compare it with the knowledge file).
export const controls = {
  '3.4.1': 'Establish and maintain baseline configurations and inventories of organizational systems (including hardware, software, firmware, and documentation) throughout the respective system development life cycles.',
  '3.4.2': 'Establish and enforce security configuration settings for information technology products employed in organizational systems.',
  '3.4.3': 'Track, review, approve or disapprove, and log changes to organizational systems.',
  '3.4.4': 'Analyze the security impact of changes prior to implementation.',
  '3.4.5': 'Define, document, approve, and enforce physical and logical access restrictions associated with changes to organizational systems.',
  '3.14.1': 'Identify, report, and correct system flaws in a timely manner.',
};

// How each control is met in practice (shown next to the requirement).
export const evidence = {
  '3.4.1': 'Recorded source snapshot, archived release builds with file manifests, and an SBOM per release.',
  '3.4.2': 'Security headers and the web-server configuration are generated and verified; repository-wide secret scan.',
  '3.4.3': 'Every change is a reviewed patch file; the owner approves by running the deploy; deploy logs are kept.',
  '3.4.4': 'The full test chain and a deploy rehearsal must pass before anything reaches production.',
  '3.4.5': 'Only the owner can deploy, and the admin console is reachable only from PDI’s internal network.',
  '3.14.1': 'Dependency advisories are checked on every run and high or critical findings block the release.',
};

const here = dirname(fileURLToPath(import.meta.url));
export const RUNS_FILE = join(here, 'pipeline-runs.json');

// Internal names to keep out of public output come from website/internal-names.txt, a file that exists only in the
// private repository (the names are themselves internal). Generic checks below still apply without it.
export const INTERNAL_NAMES_FILE = join(here, '..', '..', 'internal-names.txt');
export function internalNames() {
  try { return readFileSync(INTERNAL_NAMES_FILE, 'utf8').split('\n').map((s) => s.trim()).filter((s) => s && !s.startsWith('#')); } catch { return []; }
}
export function internalNameRegex() {
  const n = internalNames();
  return n.length ? new RegExp(n.map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'i') : null;
}
export function loadRuns() {
  try { return JSON.parse(readFileSync(RUNS_FILE, 'utf8')); } catch { return []; }
}

// Strict contract for a public run record: exact keys, typed values, nothing free-form. Returns a list of problems.
const STAGE_IDS = new Set(stages.map((s) => s.id));
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/;
const keysAre = (o, keys) => o && typeof o === 'object' && !Array.isArray(o) && Object.keys(o).sort().join(',') === [...keys].sort().join(',');
const count = (n) => Number.isInteger(n) && n >= 0 && n < 1e6;
export function validateRun(r) {
  const p = [];
  if (!keysAre(r, ['schema', 'id', 'runner', 'startedAt', 'finishedAt', 'durationSec', 'commit', 'release', 'result', 'stages', 'totals', 'sbom', 'audit'])) return ['unexpected or missing keys'];
  if (r.schema !== 1) p.push('schema');
  if (!/^(local|jenkins)-[0-9A-Za-z-]{1,40}$/.test(r.id) || !r.id.startsWith(`${r.runner}-`)) p.push('id/runner');
  if (!ISO.test(r.startedAt) || !ISO.test(r.finishedAt) || Date.parse(r.finishedAt) < Date.parse(r.startedAt)) p.push('timestamps');
  if (!(typeof r.durationSec === 'number' && r.durationSec >= 0 && r.durationSec < 86400)) p.push('durationSec');
  if (!(r.commit === null || /^[0-9a-f]{7,40}$/.test(r.commit))) p.push('commit');
  if (!(r.release === null || (keysAre(r.release, ['version']) && /^\d+\.\d+\.\d+$/.test(r.release.version)))) p.push('release');
  if (!['passed', 'failed'].includes(r.result)) p.push('result');
  if (!Array.isArray(r.stages) || !r.stages.length) p.push('stages');
  let passed = 0; let failed = 0;
  for (const s of r.stages || []) {
    if (!keysAre(s, ['id', 'result', 'durationSec', 'checks']) || !STAGE_IDS.has(s.id) || !['passed', 'failed', 'skipped', 'not-run'].includes(s.result)
      || !(typeof s.durationSec === 'number' && s.durationSec >= 0 && s.durationSec < 86400)) { p.push(`stage ${s && s.id}`); continue; }
    if (s.checks !== null) {
      if (!keysAre(s.checks, ['passed', 'failed']) || !count(s.checks.passed) || !count(s.checks.failed)) { p.push(`stage ${s.id} checks`); continue; }
      passed += s.checks.passed; failed += s.checks.failed;
    }
  }
  if (!keysAre(r.totals, ['checks', 'failed']) || r.totals.checks !== passed + failed || r.totals.failed !== failed) p.push('totals');
  if (r.result === 'passed' && (failed > 0 || (r.stages || []).some((s) => s.result === 'failed'))) p.push('result passed with failures');
  if (!(r.sbom === null || (keysAre(r.sbom, ['format', 'components']) && r.sbom.format === 'CycloneDX' && count(r.sbom.components)))) p.push('sbom');
  if (!(r.audit === null || (keysAre(r.audit, ['gate']) && ['passed', 'failed'].includes(r.audit.gate)))) p.push('audit');
  const text = JSON.stringify(r);
  if (/\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b/.test(text)) p.push('private IP');
  // Every field above is typed or enumerated, so free text cannot appear; this is a last guard against internal names.
  const internal = internalNameRegex();
  if ((internal && internal.test(text)) || /\.local\b|\.lan\b|\.internal\b/i.test(text)) p.push('internal host name');
  return p;
}
