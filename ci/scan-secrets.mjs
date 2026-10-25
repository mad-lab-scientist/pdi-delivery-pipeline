#!/usr/bin/env node
// Repository-wide secret scan (no dependencies). High-confidence credential formats and private keys only, so a
// finding is worth stopping for. Prints file:line and the pattern name, never the matched value.
//   node ci/scan-secrets.mjs            exit 1 on any finding; last line "N passed, M failed" counts DETECTORS
//                                       (a detector fails if it matches anywhere); files scanned are reported above it
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
// Not scanned: dependencies, generated output, archives and binaries, and git-ignored sensitive folders.
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', 'out', 'releases', 'backups', 'discovery']);
const SKIP_EXT = /\.(png|jpe?g|gif|ico|webp|pdf|zip|gz|tgz|xz|7z|mmdb|db|sqlite|woff2?|ttf|eot|mp4|webm|docx?|xlsx?|pptx?)$/i;
const PATTERNS = [
  ['private key', /-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----/],
  ['AWS access key id', /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/],
  ['Stripe live secret key', /\b(?:sk|rk)_live_[0-9A-Za-z]{16,}\b/],
  ['Stripe webhook secret', /\bwhsec_[0-9A-Za-z]{24,}\b/],
  ['GitHub token', /\b(?:gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{40,})\b/],
  ['GitLab token', /\bglpat-[0-9A-Za-z_-]{20}\b/],
  ['Slack token', /\bxox[abposr]-[0-9A-Za-z-]{10,}\b/],
  ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/],
  ['OpenAI or Anthropic key', /\b(?:sk-(?:proj-|ant-)?[0-9A-Za-z_-]{32,})\b/],
  ['JSON web token', /\beyJ[0-9A-Za-z_-]{10,}\.eyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}\b/],
  ['Microsoft Graph client secret', /\b[0-9A-Za-z~._-]{3}8Q~[0-9A-Za-z~._-]{31,34}\b/],
];

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((d) => {
    if (d.isDirectory()) return SKIP_DIRS.has(d.name) ? [] : walk(join(dir, d.name));
    return SKIP_EXT.test(d.name) ? [] : [join(dir, d.name)];
  });
}

let scanned = 0;
const findings = [];
const firing = new Set();
for (const f of walk(repo)) {
  if (statSync(f).size > 5 * 1024 * 1024) continue;
  scanned += 1;
  readFileSync(f, 'utf8').split('\n').forEach((line, i) => {
    for (const [name, re] of PATTERNS) if (re.test(line)) { findings.push(`${relative(repo, f).replace(/\\/g, '/')}:${i + 1}  ${name}`); firing.add(name); }
  });
}
for (const x of findings) console.log(`  FINDING  ${x}`);
console.log(`${scanned} files scanned with ${PATTERNS.length} detectors, ${findings.length} finding(s)`);
if (!scanned) { console.log('0 passed, 1 failed'); process.exit(1); }
console.log(`${PATTERNS.length - firing.size} passed, ${firing.size} failed`);
process.exit(findings.length ? 1 : 0);
