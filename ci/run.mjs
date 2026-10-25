#!/usr/bin/env node
// PDI release pipeline runner: the same stages on a PC and in Jenkins (docs/11-pipeline-showcase.md).
//   node ci/run.mjs all [--id ID] [--commit SHA] [--work DIR] [--keep-going]   every stage, then summarize
//   node ci/run.mjs <stage-id> [--id ID] [--commit SHA] [--work DIR]           one stage (Jenkins: one per stage)
//   node ci/run.mjs summarize                                                  ci/out/run.json + ci/out/public-run.json
//   node ci/run.mjs publish                                                    add the public record to the website
// Full logs stay in ci/out/logs/ (internal). The public record is built field by field and validated
// (website/src/content/pipeline.mjs validateRun) before it can be published.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stages } from './stages.mjs';
import { RUNS_FILE, loadRuns, validateRun } from '../website/src/content/pipeline.mjs';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(repo, 'ci', 'out');
const args = process.argv.slice(2);
const opt = (name, fallback) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : fallback; };
const cmd = args[0];
const stamp = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const readJson = (f) => JSON.parse(readFileSync(f, 'utf8'));
const write = (f, o) => { mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, JSON.stringify(o, null, 2) + '\n'); };

function meta({ fresh = false } = {}) {
  const f = join(OUT, 'run-meta.json');
  const id = opt('id', null);
  let m = existsSync(f) ? readJson(f) : null;
  if (fresh || !m || (id && m.id !== id)) {
    rmSync(join(OUT, 'stages'), { recursive: true, force: true });
    rmSync(join(OUT, 'logs'), { recursive: true, force: true });
    const runId = id || `local-${stamp().replace(/[-:]/g, '').replace('T', '-').replace('Z', '')}`;
    m = { id: runId, runner: runId.split('-')[0], startedAt: stamp(), commit: opt('commit', null) };
    write(f, m);
  }
  return m;
}

function hasDocker() { return spawnSync('docker', ['info'], { stdio: 'ignore' }).status === 0; }

function runStage(stage) {
  const work = resolve(opt('work', join(OUT, 'work')));
  mkdirSync(work, { recursive: true });
  const rec = { id: stage.id, result: 'passed', durationSec: 0, checks: null, startedAt: stamp() };
  process.stdout.write(`-- ${stage.name.padEnd(24)} `);
  if (stage.requires === 'docker' && !hasDocker()) {
    rec.result = 'skipped'; rec.reason = 'docker not available on this runner';
    write(join(OUT, 'stages', `${stage.id}.json`), rec); console.log('SKIPPED (no Docker)'); return rec;
  }
  const t0 = Date.now();
  let log = '';
  for (const c of stage.run) {
    const [bin, ...rest] = c.map((a) => a.replace('{repo}', repo.replace(/\\/g, '/')).replace('{work}', work));
    const r = spawnSync(bin === 'node' ? process.execPath : bin, rest, { cwd: repo, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
    log += `$ ${[bin, ...rest].join(' ')}\n${r.stdout || ''}${r.stderr || ''}\n[exit ${r.status}]\n`;
    if (r.status !== 0) { rec.result = 'failed'; break; }
  }
  rec.durationSec = Math.round((Date.now() - t0) / 100) / 10;
  const summaries = [...log.matchAll(/(\d+) passed, (\d+) failed/g)];
  if (stage.count) { const m = log.match(stage.count); if (m) rec.checks = { passed: Number(m[1]), failed: 0 }; }
  else if (summaries.length) rec.checks = summaries.map((m) => ({ passed: Number(m[1]), failed: Number(m[2]) })).reduce((a, b) => ({ passed: a.passed + b.passed, failed: a.failed + b.failed }));
  if (rec.checks && rec.checks.failed > 0) rec.result = 'failed';
  if (!rec.checks && rec.result === 'passed') rec.result = 'failed', rec.reason = 'no check summary found in the output';
  mkdirSync(join(OUT, 'logs'), { recursive: true });
  writeFileSync(join(OUT, 'logs', `${stage.id}.log`), log);
  write(join(OUT, 'stages', `${stage.id}.json`), rec);
  console.log(`${rec.result.toUpperCase().padEnd(7)} ${rec.checks ? `${rec.checks.passed} passed, ${rec.checks.failed} failed` : ''}  ${rec.durationSec}s${rec.reason ? `  (${rec.reason})` : ''}`);
  return rec;
}

function summarize() {
  const m = meta();
  const recs = stages.map((s) => {
    const f = join(OUT, 'stages', `${s.id}.json`);
    return existsSync(f) ? readJson(f) : { id: s.id, result: 'not-run', durationSec: 0, checks: null };
  });
  const deps = existsSync(join(OUT, 'deps.json')) ? readJson(join(OUT, 'deps.json')) : null;
  const builds = existsSync(join(repo, 'portal', 'build')) ? readdirSync(join(repo, 'portal', 'build')).filter((d) => /^mrpearson-v\d+\.\d+\.\d+$/.test(d)) : [];
  const version = builds.length ? readJson(join(repo, 'portal', 'build', builds.sort().pop(), 'RELEASE.json')).version : null;
  const finishedAt = stamp();
  const passed = recs.reduce((n, r) => n + (r.checks ? r.checks.passed : 0), 0);
  const failed = recs.reduce((n, r) => n + (r.checks ? r.checks.failed : 0), 0);
  const pub = {
    schema: 1,
    id: m.id,
    runner: m.runner,
    startedAt: m.startedAt,
    finishedAt,
    durationSec: Math.round(recs.reduce((n, r) => n + r.durationSec, 0) * 10) / 10,
    commit: m.commit && /^[0-9a-f]{7,40}$/.test(m.commit) ? m.commit.slice(0, 12) : null,
    release: version ? { version } : null,
    result: recs.every((r) => r.result === 'passed' || r.result === 'skipped') && failed === 0 ? 'passed' : 'failed',
    stages: recs.map((r) => ({ id: r.id, result: r.result, durationSec: r.durationSec, checks: r.checks ? { passed: r.checks.passed, failed: r.checks.failed } : null })),
    totals: { checks: passed + failed, failed },
    sbom: deps && Number.isInteger(deps.components) ? { format: 'CycloneDX', components: deps.components } : null,
    audit: deps && deps.audit ? { gate: deps.audit.gate } : null,
  };
  const problems = validateRun(pub);
  if (problems.length) { console.error(`public record rejected: ${problems.join(', ')}`); process.exit(1); }
  write(join(OUT, 'run.json'), { ...pub, internal: { stages: recs, deps } });
  write(join(OUT, 'public-run.json'), pub);
  console.log(`== run ${pub.id}: ${pub.result.toUpperCase()}, ${pub.totals.checks} checks, ${pub.totals.failed} failed, ${pub.durationSec}s -> ci/out/public-run.json`);
  return pub;
}

function publish() {
  const pub = readJson(join(OUT, 'public-run.json'));
  const problems = validateRun(pub);
  if (problems.length) { console.error(`not published: ${problems.join(', ')}`); process.exit(1); }
  const runs = [pub, ...loadRuns().filter((r) => r.id !== pub.id)].slice(0, 20);
  writeFileSync(RUNS_FILE, JSON.stringify(runs, null, 2) + '\n');
  console.log(`published ${pub.id} to ${RUNS_FILE.replace(repo, '.')} (${runs.length} runs kept); it ships with the next website release`);
}

if (cmd === 'all') {
  meta({ fresh: true });
  let ok = true;
  for (const s of stages) {
    if (!ok && !args.includes('--keep-going')) { console.log(`-- ${s.name.padEnd(24)} not run (an earlier stage failed)`); continue; }
    if (runStage(s).result === 'failed') ok = false;
  }
  const pub = summarize();
  process.exit(pub.result === 'passed' ? 0 : 1);
} else if (cmd === 'summarize') {
  summarize();
} else if (cmd === 'publish') {
  publish();
} else if (stages.some((s) => s.id === cmd)) {
  meta();
  process.exit(runStage(stages.find((s) => s.id === cmd)).result === 'failed' ? 1 : 0);
} else {
  console.log(`usage: node ci/run.mjs all | summarize | publish | ${stages.map((s) => s.id).join(' | ')}`);
  process.exit(cmd ? 1 : 0);
}
