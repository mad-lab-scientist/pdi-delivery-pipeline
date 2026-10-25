#!/usr/bin/env node
// mrpearson.net static build (zero dependencies).
//   node build.mjs            -> website/dist/
// Output: one index.html per route (e.g. dist/pricing/index.html), fingerprinted assets under /assets/,
// sitemap.xml, robots.txt, and _drafts/ for pages that are not approved for publication yet.
import { createHash } from 'node:crypto';
import { mkdirSync, rmSync, readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { layout } from './src/templates/layout.mjs';
import { allPages, orgJsonLd } from './src/templates/pages.mjs';
import { site } from './src/content/site.mjs';
import { buildLlms } from './src/templates/llms.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const SRC_ASSETS = join(here, 'src', 'assets');

function walk(dir) {
  return readdirSync(dir).flatMap((f) => { const p = join(dir, f); return statSync(p).isDirectory() ? walk(p) : [p]; });
}
function write(file, content) { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, content); }

export function build({ outDir = join(here, 'dist') } = {}) {
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });

  // Fingerprinted assets: /assets/<path>?v=<hash> (same file name, so nginx/Express static needs no rewrite rules).
  const assets = {};
  for (const file of walk(SRC_ASSETS)) {
    const rel = relative(SRC_ASSETS, file).replace(/\\/g, '/');
    const buf = readFileSync(file);
    const hash = createHash('sha256').update(buf).digest('hex').slice(0, 10);
    write(join(outDir, 'assets', rel), buf);
    assets[rel] = `/assets/${rel}?v=${hash}`;
  }

  const pages = allPages();
  const published = pages.filter((p) => !p.draft);
  // Footer links only for legal pages that have been approved (published).
  const legalLabels = { privacy: 'Privacy', terms: 'Terms', security: 'Security' };
  const legalLinks = published.filter((p) => p.legal).map((p) => ({ href: p.path, label: legalLabels[p.legal] }));
  const report = [];
  for (const p of pages) {
    const html = layout({ ...p, assets, legalLinks });
    let file;
    if (p.draft) file = join(outDir, '_drafts', p.path.slice(1), 'index.html');
    else if (p.path === '/') file = join(outDir, 'index.html');
    else if (p.path === '/404') file = join(outDir, '404.html');
    else file = join(outDir, p.path.slice(1), 'index.html');
    write(file, html);
    report.push({ path: p.path, file: relative(outDir, file).replace(/\\/g, '/'), bytes: Buffer.byteLength(html), draft: !!p.draft, noindex: !!p.noindex });
  }

  const today = new Date().toISOString().slice(0, 10);
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${published
    .filter((p) => !p.noindex)
    .map((p) => `  <url><loc>${site.url}${p.path === '/' ? '/' : p.path}</loc><lastmod>${today}</lastmod></url>`)
    .join('\n')}\n</urlset>\n`;
  write(join(outDir, 'sitemap.xml'), sitemap);
  write(join(outDir, 'robots.txt'), `User-agent: *\nAllow: /\nDisallow: /api/\nDisallow: /admin\nDisallow: /portal\nDisallow: /payment/success\nDisallow: /_drafts/\n\nSitemap: ${site.url}/sitemap.xml\n`);
  write(join(outDir, 'llms.txt'), buildLlms());
  // Same organization graph the pages embed; the admin console's SEO tools link to /schema.jsonld.
  write(join(outDir, 'schema.jsonld'), JSON.stringify(orgJsonLd, null, 2) + '\n');
  // RFC 9116 security.txt: Contact and Expires are required; Expires must be less than a year out,
  // so every build refreshes it (and a stale deploy naturally signals that it needs review).
  const expires = new Date(Date.now() + 364 * 86400000).toISOString().replace(/\.\d{3}Z$/, '.000Z');
  const securityPublished = published.some((p) => p.legal === 'security');
  write(join(outDir, '.well-known', 'security.txt'), [
    `Contact: mailto:${site.email}`,
    `Expires: ${expires}`,
    'Preferred-Languages: en',
    `Canonical: ${site.url}/.well-known/security.txt`,
    ...(securityPublished ? [`Policy: ${site.url}/security`] : []),
    '',
  ].join('\n'));
  write(join(outDir, '_build-report.json'), JSON.stringify({ built: new Date().toISOString(), assets, pages: report }, null, 2));
  return { outDir, assets, pages: report };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const r = build();
  const total = r.pages.reduce((s, p) => s + p.bytes, 0);
  console.log(`Built ${r.pages.length} pages (${r.pages.filter((p) => p.draft).length} drafts) into ${r.outDir}`);
  for (const p of r.pages) console.log(`  ${p.draft ? '[draft] ' : ''}${p.path.padEnd(42)} ${(p.bytes / 1024).toFixed(1).padStart(6)} KB`);
  console.log(`  total HTML ${(total / 1024).toFixed(1)} KB`);
}
