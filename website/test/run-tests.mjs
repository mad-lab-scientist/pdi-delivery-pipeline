#!/usr/bin/env node
// mrpearson.net test suite (zero dependencies).  node website/test/run-tests.mjs
// 1) Fact parity: the site must match the authoritative knowledge files (rate card, SLA, CMMC, NAICS, profile).
// 2) Truth guards: no unapproved dollar amounts, no withdrawn claims (24/7, unlimited, fake live stats...).
// 3) Engineering: CSP-safe markup, valid structure, working links, drafts isolated, no internal IPs or secrets,
//    WCAG AA contrast for design tokens, page-weight budgets, JS syntax.
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { build } from '../build.mjs';
import { tiers, tierById, serviceRates, premiums, blocks, blockExample, marketRefs } from '../src/content/pricing.mjs';
import { sla } from '../src/content/sla.mjs';
import { cmmc } from '../src/content/defense.mjs';
import { site } from '../src/content/site.mjs';
import { services } from '../src/content/services.mjs';
import { stages as pipelineStages, controls as nistControls, loadRuns, validateRun, internalNames, internalNameRegex } from '../src/content/pipeline.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, '..');
const repo = join(web, '..');
// Public showcase mode (PDI_PUBLIC_SHOWCASE=1): internal source documents (rate-card derivation, playbooks, company
// profile) are not in the public repository, so the tests that compare against them are reported as SKIPPED with the
// reason. Without the flag a missing document is a failure, as before.
const SHOWCASE = process.env.PDI_PUBLIC_SHOWCASE === '1';
class Skip extends Error {}
const kb = (p) => {
  const f = join(repo, 'knowledge', p);
  if (SHOWCASE && !existsSync(f)) return null;
  return readFileSync(f, 'utf8');
};
const need = (...docs) => { if (docs.some((d) => d === null)) throw new Skip('internal source document, not in the public repository'); };
const norm = (s) => s.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/\*\*/g, '').replace(/\s+/g, ' ').trim();

let failed = 0, passed = 0, skipped = 0;
function test(name, fn) {
  try { fn(); passed++; console.log(`  [PASS] ${name}`); }
  catch (err) {
    if (err instanceof Skip) { skipped++; console.log(`  [SKIP] ${name} (${err.message})`); return; }
    failed++; console.log(`  [FAIL] ${name}\n         ${String(err.message).split('\n').join('\n         ')}`);
  }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function eq(a, b, msg) { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n expected ${JSON.stringify(b)}\n actual   ${JSON.stringify(a)}`); }

// ------------------------------------------------------------------ build
console.log('\n== Build');
const out = join(web, 'dist');
const result = build({ outDir: out });
const pages = result.pages.map((p) => ({ ...p, html: readFileSync(join(out, p.file), 'utf8') }));
const published = pages.filter((p) => !p.draft);
// Block-level boundaries become line breaks, so every list item, cell, heading and paragraph is judged on its own.
const textOf = (html) => html.replace(/<script[\s\S]*?<\/script>/g, ' ').replace(/<style[\s\S]*?<\/style>/g, ' ')
  .replace(/<\/?(li|p|h[1-6]|td|th|tr|dt|dd|summary|details|div|section|header|footer|nav|ul|ol|table|caption|br|address|form|label|option)\b[^>]*>/gi, '\n')
  .replace(/<[^>]+>/g, ' ')
  .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/[ \t]+/g, ' ').replace(/\s*\n\s*/g, '\n');
console.log(`  built ${pages.length} pages (${pages.length - published.length} drafts)`);

// ------------------------------------------------------------------ fact parity
console.log('\n== Fact parity with knowledge/ (authoritative)');
const rateCardMd = kb('pdi-company-core/08-labor-rate-card.md');
const slaMd = kb('pdi-company-core/04-sla-and-priority-matrix.md');
const cmmcMd = kb('pdi-executive-playbooks/03-cmmc-2-readiness-playbook.md');
const govMd = kb('pdi-executive-playbooks/08-government-contracting-playbook.md');
const profileMd = kb('pdi-company-core/01-company-profile.md');

test('Labor tiers and rates match the Labor Rate Card table', () => {
  need(rateCardMd);
  const rows = [...rateCardMd.matchAll(/^\| \*\*(.+?)\*\* \| .+? \| \*\*\$(\d+)\*\* \|$/gm)].map((m) => [m[1], Number(m[2])]);
  assert(rows.length === 9, `expected 9 tier rows in the rate card, found ${rows.length}`);
  eq(tiers.map((t) => [t.name, t.rate]), rows, 'tiers differ from the rate card');
});

test('Rate per service line matches "Which rate applies"', () => {
  need(rateCardMd);
  const map = {
    'Help Desk & Support': 'help-desk', 'Infrastructure & Servers': 'infrastructure', 'Network Management (Fortinet, VLAN, VPN, SD-WAN)': 'network-management',
    'Cloud Solutions (Azure, AWS, M365 migrations)': 'cloud-solutions', 'DevOps & CI/CD Automation': 'devops-ci-cd', 'Private Cloud & Virtualization (Proxmox)': 'private-cloud-virtualization',
    'Secure Hosting & Web Operations': 'secure-hosting', 'Backup & Disaster Recovery': 'backup-recovery', 'Cybersecurity': 'cybersecurity',
    'SOC Monitoring & Log Management': 'soc-monitoring-log-management', 'Compliance Readiness & Evidence': 'compliance-readiness-evidence',
    'AI Automation & Operations': 'ai-automation-operations', 'VPS Hosting': 'vps-hosting',
  };
  const section = rateCardMd.split('## Which rate applies')[1].split('## Premiums')[0];
  let checked = 0;
  for (const m of section.matchAll(/^\| ([^|]+?) \| ([^|]+?) \|$/gm)) {
    const slug = map[m[1].trim()];
    if (!slug) continue;
    const docAmounts = [...new Set([...m[2].matchAll(/\$(\d+)/g)].map((x) => Number(x[1])))].sort();
    const siteAmounts = [...new Set(serviceRates[slug].map(([id]) => tierById[id].rate))].sort();
    eq(siteAmounts, docAmounts, `rates for ${slug}`);
    checked++;
  }
  eq(checked, Object.keys(map).length, 'service lines checked');
  eq(Object.keys(serviceRates).sort(), services.map((s) => s.slug).sort(), 'every service has a rate mapping');
});

test('Premiums, minimums and travel match the rate card', () => {
  need(rateCardMd);
  const doc = norm(rateCardMd);
  for (const s of ['1.25×', '1.5×', '2×, 2-hour minimum on-site', '15-minute increments, 30-minute minimum', '1-hour minimum', 'beyond 30 minutes each way billed at T1']) assert(doc.includes(s), `rate card no longer says "${s}"`);
  const ours = premiums.map((p) => p.policy).join(' | ');
  for (const s of ['1.25×', '1.5×', '2×', '2-hour minimum', '15-minute increments, 30-minute minimum', '1-hour minimum', 'beyond 30 minutes each way', 'T1 rate']) assert(ours.includes(s), `site premiums missing "${s}"`);
});

test('Prepaid block hours match the rate card, and the examples are computed correctly', () => {
  need(rateCardMd);
  const doc = norm(rateCardMd);
  assert(doc.includes('20 h equivalent 10% off') && doc.includes('40 h equivalent 15% off') && doc.includes('12-month expiry'), 'rate card block terms changed');
  eq(blocks.sizes, [{ hours: 20, discount: 0.1 }, { hours: 40, discount: 0.15 }], 'block sizes');
  eq(blocks.expiryMonths, 12, 'block expiry');
  const a = blockExample(20, 0.1), b = blockExample(40, 0.15);
  eq([a.list, a.price, a.saved], [3500, 3150, 350], '20-hour T2 example');
  eq([b.list, b.price, b.saved], [7000, 5950, 1050], '40-hour T2 example');
});

test('SLA response targets match SLA v2.0', () => {
  need(slaMd);
  const rows = [...slaMd.matchAll(/^\| \*\*(P\d) \w+\*\* \| .+? \| \*\*(.+?)\*\*(?: \([^)]*\))? \|/gm)].map((m) => [m[1], m[2]]);
  eq(rows.length, 4, 'priority rows parsed from the SLA doc');
  eq(sla.priorities.map((p) => [p.p, p.response]), rows.map(([p, r]) => [p, r[0].toUpperCase() + r.slice(1)]), 'response targets');
  const doc = norm(slaMd);
  for (const s of ['Monday–Friday, 8:00 AM–6:00 PM Central', 'target response within 2 hours', "Tuesday and Thursday, 6:00–10:00 PM Central", "2 business days' notice", '≥ 95%', 'No financial service credits during the first 12 months']) assert(doc.includes(s), `SLA doc no longer says "${s}"`);
  const ours = norm(JSON.stringify(sla));
  for (const s of ['Monday–Friday, 8:00 AM–6:00 PM Central', 'target response within 2 hours', 'Tuesday and Thursday, 6:00–10:00 PM Central', "2 business days' notice", 'at least 95%', 'No financial service credits are offered during the first 12 months']) assert(ours.includes(s), `site SLA missing "${s}"`);
});

test('CMMC dates and facts match the CMMC playbook', () => {
  need(cmmcMd);
  const doc = norm(cmmcMd);
  for (const p of cmmc.phases) assert(doc.includes(`| ${p.n} | ${p.start} |`), `phase ${p.n} start "${p.start}" not in playbook`);
  assert(doc.includes('| 2 | Nov 10, 2026 | Level 2 C3PAO certification'), 'phase 2 definition changed');
  eq(cmmc.phase2.date, '2026-11-10', 'phase 2 ISO date');
  for (const s of ['−203 to 110', 'within 72 hours', '110 requirements of NIST SP 800-171 Rev 2', '15 basic safeguarding requirements (FAR 52.204-21)', 'every 3 years']) assert(doc.includes(s), `playbook no longer says "${s}"`);
});

test('NAICS codes and size standards match the Government Contracting Playbook', () => {
  need(govMd);
  const rows = [...govMd.matchAll(/^\| \**(\d{6})\** \| [^|]+ \| \**(\$[\d.]+M)/gm)].map((m) => [m[1], m[2]]);
  eq(site.naics.map((n) => [n.code, n.size]), rows, 'NAICS table');
  assert(site.naics[0].primary && site.naics[0].code === '541512', 'primary NAICS must be 541512');
});

test('Company identity matches the Company Profile', () => {
  need(profileMd);
  for (const s of [site.legalName, 'Pearson Cyber Defense', site.phone, site.email, site.address.street, site.tagline]) assert(profileMd.includes(s), `profile does not contain "${s}"`);
});

// ------------------------------------------------------------------ truth guards
console.log('\n== Truth guards (all pages, drafts included)');
const allText = pages.map((p) => ({ path: p.path, text: textOf(p.html) }))
  .concat([{ path: '/llms.txt', text: readFileSync(join(out, 'llms.txt'), 'utf8') }])
  .concat([{ path: '/schema.jsonld', text: readFileSync(join(out, 'schema.jsonld'), 'utf8') }]);

test('Every dollar amount on the site is an approved figure', () => {
  const allowed = new Set();
  const add = (n) => allowed.add(String(n).replace(/,/g, ''));
  tiers.forEach((t) => add(t.rate));
  blocks.sizes.forEach((s) => { const x = blockExample(s.hours, s.discount); [x.list, x.price, x.saved].forEach(add); });
  marketRefs.forEach((m) => [...m.figure.matchAll(/\$([\d,]+)/g)].forEach((x) => add(x[1])));
  site.naics.forEach((n) => add(n.size.replace('$', '')));
  add(25); // invoice minimum (existing checkout rule)
  const bad = [];
  for (const { path, text } of allText) for (const m of text.matchAll(/\$\s?([\d,]+(?:\.\d+)?M?)/g)) if (!allowed.has(m[1].replace(/,/g, ''))) bad.push(`${path}: $${m[1]}`);
  assert(!bad.length, `unapproved amounts:\n${[...new Set(bad)].join('\n')}`);
});

test('No withdrawn or inflated claims', () => {
  const banned = [/unlimited/i, /military-grade/i, /enterprise empire/i, /digital guard detail/i, /digital fortress/i, /acts of god/i, /survives anything/i, /global NOC/i, /engineer pod/i, /dedicated (team|engineers?|pod|account manager)/i,
    /99\.\d+\s?%/, /signals processed/i, /assets watched/i, /tickets resolved/i, /SLA compliance/i, /\bour (team|technicians|engineers|staff)\b/i, /\btechnicians\b/i,
    /15-minute (SLA|response|critical)/i, /30-minute (SLA|critical)/i, /on-site engineer option/i, /guaranteed (pass|response)/i, /\bwe certify\b/i,
    /\b(we are|we're|PDI is|is) (CMMC|SOC 2) (certified|compliant)/i];
  const hits = [];
  for (const { path, text } of allText) for (const re of banned) { const m = text.match(re); if (m) hits.push(`${path}: "${m[0]}"`); }
  assert(!hits.length, hits.join('\n'));
});

// Sentences are checked individually. Questions (FAQ prompts) are exempt; their answers are checked as statements.
const NEG = /\b(no|not|never|doesn['’]t|does not|isn['’]t|aren['’]t|won['’]t|can['’]t)\b/i;

test('"24/7", "certif…" and "guarantee" only appear in honest, negated or explanatory sentences', () => {
  const issues = [];
  for (const { path, text } of allText) {
    for (const s of text.split(/\n+|(?<=[.!?])\s+/)) {
      if (s.trim().endsWith('?')) continue;
      if (/24\s*\/\s*7|24x7|round-the-clock|around the clock/i.test(s) && !(NEG.test(s) || /provider|scope/i.test(s))) issues.push(`${path}: ${s.trim().slice(0, 140)}`);
      if (/\bcertif(y|ied|ies|ication|ications)\b/i.test(s) && !(NEG.test(s) || /C3PAO|CPA firm|DIBCAC|requires? |required/i.test(s))) issues.push(`${path}: ${s.trim().slice(0, 140)}`);
      if (/guarant/i.test(s) && !NEG.test(s)) issues.push(`${path}: ${s.trim().slice(0, 140)}`);
    }
  }
  assert(!issues.length, [...new Set(issues)].join('\n'));
});

test('Readiness badges stay readiness language (never "certified")', () => {
  for (const b of site.readinessBadges) assert(!/certif/i.test(b), `badge "${b}"`);
});

// ------------------------------------------------------------------ engineering
console.log('\n== Engineering');
test('CSP-safe markup: no inline JS, no inline handlers or styles, scripts only from /assets/', () => {
  const issues = [];
  for (const p of pages) {
    for (const m of p.html.matchAll(/<script\b([^>]*)>/g)) {
      const attrs = m[1];
      if (/type="application\/ld\+json"/.test(attrs)) continue;
      if (!/src="\/assets\/js\/[a-z-]+\.js\?v=[0-9a-f]{10}"/.test(attrs)) issues.push(`${p.path}: <script${attrs}>`);
    }
    if (/\son[a-z]+\s*=/i.test(p.html)) issues.push(`${p.path}: inline event handler`);
    if (/javascript:/i.test(p.html)) issues.push(`${p.path}: javascript: URL`);
    if (/\sstyle\s*=/i.test(p.html)) issues.push(`${p.path}: style attribute`);
    for (const m of p.html.matchAll(/<link\b[^>]*rel="stylesheet"[^>]*href="([^"]+)"/g)) if (!/^\/assets\/|^https:\/\/fonts\.googleapis\.com\//.test(m[1])) issues.push(`${p.path}: stylesheet ${m[1]}`);
  }
  assert(!issues.length, issues.join('\n'));
});

test('Page structure, titles, descriptions and form labels', () => {
  const issues = [];
  for (const p of pages) {
    const h = p.html;
    if (!h.startsWith('<!DOCTYPE html>')) issues.push(`${p.path}: doctype`);
    if (!h.includes('<html lang="en">')) issues.push(`${p.path}: lang`);
    const h1 = (h.match(/<h1[\s>]/g) || []).length; if (h1 !== 1) issues.push(`${p.path}: ${h1} <h1>`);
    const title = ((h.match(/<title>([^<]*)<\/title>/) || [])[1] || '').replace(/&amp;/g, '&');
    if (!title || title.length > 65) issues.push(`${p.path}: title length ${title.length} "${title}"`);
    const desc = (h.match(/<meta name="description" content="([^"]*)"/) || [])[1] || '';
    if (desc.length < 50 || desc.length > 165) issues.push(`${p.path}: description length ${desc.length}`);
    if (!/<link rel="canonical" href="https:\/\/mrpearson\.net\//.test(h)) issues.push(`${p.path}: canonical`);
    const ids = [...h.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);
    const dup = ids.filter((x, i) => ids.indexOf(x) !== i); if (dup.length) issues.push(`${p.path}: duplicate ids ${[...new Set(dup)]}`);
    for (const m of h.matchAll(/<(input|select|textarea)\b([^>]*)>/g)) {
      if (/type="hidden"/.test(m[2])) continue;
      const id = (m[2].match(/\sid="([^"]+)"/) || [])[1];
      if (!id || !h.includes(`<label for="${id}"`)) issues.push(`${p.path}: unlabeled ${m[1]} ${id || ''}`);
    }
    for (const m of h.matchAll(/<button\b([^>]*)>/g)) if (!/type="(button|submit)"/.test(m[1])) issues.push(`${p.path}: button without type`);
    for (const m of h.matchAll(/<a\b([^>]*)target="_blank"([^>]*)>/g)) if (!/rel="[^"]*noopener/.test(m[1] + m[2])) issues.push(`${p.path}: target=_blank without noopener`);
    for (const m of h.matchAll(/<img\b([^>]*)>/g)) if (!/\salt="/.test(m[1])) issues.push(`${p.path}: img without alt`);
  }
  assert(!issues.length, issues.join('\n'));
});

test('Internal links and fragment targets resolve', () => {
  const appRoutes = new Set(['/login', '/register', '/app', '/icons/app-icon-180.png']);
  const byPath = Object.fromEntries(pages.map((p) => [p.path, p]));
  const issues = [];
  for (const p of published) {
    for (const m of p.html.matchAll(/\s(?:href|src)="(\/[^"]*)"/g)) {
      const raw = m[1];
      if (raw.startsWith('//')) { issues.push(`${p.path}: protocol-relative ${raw}`); continue; }
      const [pathPart, frag] = raw.split('#');
      const clean = pathPart.split('?')[0] || p.path;
      if (appRoutes.has(clean)) continue;
      if (clean.startsWith('/assets/') || clean.startsWith('/.well-known/')) { if (!existsSync(join(out, clean))) issues.push(`${p.path}: missing file ${clean}`); continue; }
      const target = byPath[clean];
      if (!target) { issues.push(`${p.path}: broken link ${raw}`); continue; }
      if (target.draft) issues.push(`${p.path}: links to draft ${clean}`);
      if (frag && !new RegExp(`\\sid="${frag}"`).test(target.html)) issues.push(`${p.path}: missing #${frag} on ${clean}`);
    }
  }
  assert(!issues.length, issues.join('\n'));
});

test('Drafts are isolated (noindex, banner, not in sitemap) and /admin is never linked', () => {
  const sitemap = readFileSync(join(out, 'sitemap.xml'), 'utf8');
  const robots = readFileSync(join(out, 'robots.txt'), 'utf8');
  for (const d of pages.filter((p) => p.draft)) {
    assert(d.file.startsWith('_drafts/'), `${d.path} not under _drafts/`);
    assert(d.html.includes('noindex') && d.html.includes('DRAFT, pending attorney review'), `${d.path} missing noindex or draft banner`);
    assert(!sitemap.includes(`mrpearson.net${d.path}<`), `${d.path} in sitemap`);
  }
  for (const p of published.filter((x) => !x.noindex)) assert(sitemap.includes(`<loc>${site.url}${p.path === '/' ? '/' : p.path}</loc>`), `sitemap missing ${p.path}`);
  assert(/Disallow: \/api\//.test(robots) && /Disallow: \/admin/.test(robots), 'robots.txt must disallow /api/ and /admin');
  for (const p of pages) assert(!/href="\/admin/.test(p.html), `${p.path} links to /admin`);
});

test('Legal pages: no unresolved ⟦CONFIRM⟧ on any published page; drafts keep the banner; footer links only approved pages', () => {
  const issues = [];
  for (const p of published) if (p.html.includes('⟦')) issues.push(`${p.path}: unresolved ⟦…⟧ marker on a published page`);
  const legal = pages.filter((p) => ['/privacy', '/terms', '/security'].includes(p.path));
  eq(legal.length, 3, 'privacy, terms and security pages exist');
  for (const p of legal.filter((x) => x.draft)) {
    for (const q of published) if (new RegExp(`href="${p.path}"`).test(q.html)) issues.push(`${q.path} links to draft ${p.path}`);
  }
  assert(!issues.length, issues.join('\n'));
});

test('security.txt follows RFC 9116 (Contact, Expires < 1 year, Canonical; Policy only when published)', () => {
  const txt = readFileSync(join(out, '.well-known', 'security.txt'), 'utf8');
  assert(/^Contact: mailto:admin@mrpearson\.net$/m.test(txt), 'Contact');
  const exp = Date.parse((txt.match(/^Expires: (.+)$/m) || [])[1]);
  assert(exp > Date.now() && exp - Date.now() < 365 * 86400000, 'Expires must be in the future and less than a year away');
  assert(/^Canonical: https:\/\/mrpearson\.net\/\.well-known\/security\.txt$/m.test(txt), 'Canonical');
  const secPublished = published.some((p) => p.path === '/security');
  assert(/^Policy: /m.test(txt) === secPublished, 'Policy line must appear only when /security is published');
});

test('Pipeline: published runs pass the strict record contract, newest first, at most 20', () => {
  const runs = loadRuns();
  const issues = [];
  runs.forEach((r, i) => { const p = validateRun(r); if (p.length) issues.push(`${r.id || i}: ${p.join(', ')}`); });
  assert(!issues.length, issues.join('\n'));
  assert(runs.length <= 20, 'more than 20 runs kept');
  assert(new Set(runs.map((r) => r.id)).size === runs.length, 'duplicate run ids');
  for (let i = 1; i < runs.length; i++) assert(runs[i - 1].finishedAt >= runs[i].finishedAt, 'runs are not newest first');
  // Every stage the page describes has a command in ci/stages.mjs (that module throws if they drift apart).
  const ci = spawnSync(process.execPath, ['-e', "import('./ci/stages.mjs').then(m => console.log(m.stages.length))"], { cwd: repo, encoding: 'utf8' });
  assert(ci.status === 0 && Number(ci.stdout.trim()) === pipelineStages.length, `ci/stages.mjs does not match the public stages: ${ci.stderr.slice(0, 200)}`);
});

test('Pipeline: /engineering shows exactly the latest run and the NIST text verbatim', () => {
  const page = published.find((p) => p.path === '/engineering');
  assert(page, '/engineering missing');
  const t = textOf(page.html);
  for (const s of pipelineStages) assert(t.includes(s.name), `stage missing on the page: ${s.name}`);
  const runs = loadRuns();
  if (runs.length) {
    const r = runs[0];
    assert(t.includes(`${r.totals.checks - r.totals.failed} / ${r.totals.checks}`), 'latest run totals not shown');
    assert(t.includes(r.id), 'latest run id not shown');
    assert(!r.stages.some((s) => s.result === 'failed') || /Failed/.test(t), 'a failed run must be shown as failed');
  }
  const nistMd = kb('pdi-executive-playbooks/09-nist-sp800-171r2-requirements.md');
  need(nistMd);
  for (const [id, text] of Object.entries(nistControls)) {
    const m = nistMd.match(new RegExp(`^- \\*\\*${id.replace(/\./g, '\\.')}\\*\\* · .+? · (?:Basic|Derived) requirement: (.+)$`, 'm'));
    assert(m, `NIST ${id} not found in the knowledge file`);
    eq(text, m[1].trim(), `NIST ${id} wording differs from the knowledge file`);
    assert(t.includes(text), `NIST ${id} text not on the page`);
  }
  for (const s of pipelineStages) for (const c of s.controls) assert(nistControls[c], `stage ${s.id} cites ${c}, which has no requirement text`);
  // Deploys are approved and run by a person: no claim of automatic deployment.
  assert(!/fully automated deploy|continuous deployment|deploys automatically|auto-deploy/i.test(t), 'claims automated deployment');
});

test('schema.jsonld is valid schema.org JSON matching the site facts', () => {
  const j = JSON.parse(readFileSync(join(out, 'schema.jsonld'), 'utf8'));
  eq(j['@context'], 'https://schema.org', '@context');
  eq(j.url, 'https://mrpearson.net', 'url');
  eq(j.email, 'admin@mrpearson.net', 'email');
  eq(j.telephone, '+1-256-675-9961', 'telephone');
  assert(!/offer|price/i.test(JSON.stringify(j)), 'no offers or prices in structured data');
});

test('Internal-name list present in the private repository (it is what the output checks below compare against)', () => {
  if (SHOWCASE) throw new Skip('the list is internal and stays in the private repository');
  assert(internalNames().length >= 5, `website/internal-names.txt missing or too short (${internalNames().length} names)`);
});

test('No internal network details or secrets in the output', () => {
  const internal = internalNameRegex();
  const issues = [];
  const files = (function walk(d) { return readdirSync(d).flatMap((f) => { const x = join(d, f); return statSync(x).isDirectory() ? walk(x) : [x]; }); })(out);
  for (const f of files) {
    if (!/\.(html|css|js|xml|txt|svg|jsonld)$/.test(f)) continue;
    const s = readFileSync(f, 'utf8');
    const rel = relative(out, f);
    if (/\b(192\.168|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.)/.test(s)) issues.push(`${rel}: private IP`);
    if ((internal && internal.test(s)) || /vlan\s?\d+/i.test(s)) issues.push(`${rel}: internal host or lab detail`);
    if (/sk_live_|rk_live_|whsec_|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}/.test(s)) issues.push(`${rel}: secret-like string`);
  }
  assert(!issues.length, issues.join('\n'));
});

test('Design tokens meet WCAG AA contrast (4.5:1) for text', () => {
  const css = readFileSync(join(web, 'src/assets/css/site.css'), 'utf8');
  const tok = Object.fromEntries([...css.split(':root')[1].split('}')[0].matchAll(/--([\w-]+):\s*(#[0-9a-f]{6})/gi)].map((m) => [m[1], m[2]]));
  const lum = (hex) => { const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const pairs = [['text', 'bg'], ['text-2', 'bg'], ['muted', 'bg'], ['muted', 'panel'], ['muted', 'panel-2'], ['text-2', 'panel-2'], ['cyan', 'bg'], ['cyan', 'panel'], ['green', 'bg'], ['red', 'panel'], ['amber', 'bg'], ['on-accent', 'cyan'], ['on-accent', 'green']];
  const low = pairs.map(([f, b]) => [f, b, ratio(tok[f], tok[b])]).filter(([, , r]) => r < 4.5);
  assert(!low.length, low.map(([f, b, r]) => `${f} on ${b}: ${r.toFixed(2)}:1`).join('\n'));
});

test('Weight budgets: HTML ≤ 60 KB per page, CSS ≤ 60 KB, JS ≤ 30 KB', () => {
  const big = pages.filter((p) => p.bytes > 60 * 1024).map((p) => `${p.path} ${(p.bytes / 1024).toFixed(1)} KB`);
  assert(!big.length, big.join('\n'));
  const size = (rel) => statSync(join(out, 'assets', rel)).size;
  assert(size('css/site.css') <= 60 * 1024, `CSS ${size('css/site.css')} bytes`);
  const js = size('js/site.js') + size('js/network.js');
  assert(js <= 30 * 1024, `JS ${js} bytes`);
});

test('JavaScript parses (node --check)', () => {
  for (const f of ['site.js', 'network.js']) {
    const r = spawnSync(process.execPath, ['--check', join(web, 'src/assets/js', f)], { encoding: 'utf8' });
    assert(r.status === 0, `${f}: ${r.stderr}`);
  }
});

if (skipped) console.log(`\n${skipped} skipped (public showcase: internal source documents are not published)`);
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
