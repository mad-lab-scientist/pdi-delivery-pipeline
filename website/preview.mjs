#!/usr/bin/env node
// Local preview of website/dist with production-like security headers and MOCK API endpoints.
//   node preview.mjs           -> http://127.0.0.1:4173
// The mocks only answer locally so forms can be exercised; nothing is sent anywhere.
import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from './build.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, 'dist');
const PORT = Number(process.env.PORT || 4173);
build({ outDir: dist });

const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.xml': 'application/xml', '.txt': 'text/plain; charset=utf-8', '.json': 'application/json', '.png': 'image/png' };
// Same policy family as production (script-src 'self'; no inline script needed by the new pages).
const CSP = "default-src 'self'; script-src 'self'; script-src-attr 'none'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'self'; form-action 'self' https://checkout.stripe.com";

function send(res, status, body, type) {
  res.writeHead(status, { 'Content-Type': type, 'Content-Security-Policy': CSP, 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin', 'X-Frame-Options': 'DENY', 'Cache-Control': 'no-store' });
  res.end(body);
}
// Routes owned by the existing Node app on the live server (client portal, admin portal, Stripe return pages).
// They aren't part of this static site, so the preview explains that and links to the live page.
const APP_ROUTE = /^\/(login|register|app|admin)(\/|$)|^\/payment\//;
function appRoutePage(path) {
  const report = JSON.parse(readFileSync(join(dist, '_build-report.json'), 'utf8'));
  const live = `https://mrpearson.net${path}`;
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">
<title>Live app route (preview) | Pearson Cyber Defense</title><link rel="stylesheet" href="${report.assets['css/site.css']}"></head>
<body><main id="main"><section class="section notfound"><div class="container narrow">
<div class="terminal"><div class="terminal-bar"><span></span><span></span><span></span><p class="mono">local preview</p></div>
<ol class="terminal-body"><li class="t-cmd">$ open ${esc(live)}</li><li class="t-out">[preview] ${esc(path)} is served by the live portal app,</li><li class="t-out">          not by this static preview of the public pages.</li><li class="t-ok">✓ the live page is up; open it below</li></ol></div>
<h1>This page lives on the live server</h1>
<p class="lead">Client login, account creation, the client app and the admin portal belong to the existing mrpearson.net application. They are unchanged by the v2 public site and keep working when it deploys.</p>
<div class="btn-row"><a class="btn btn-primary" href="${esc(live)}" target="_blank" rel="noopener">Open ${esc(path)} on the live site</a><a class="btn btn-ghost" href="/">Back to the preview</a></div>
</div></section></main></body></html>`;
}

function readBody(req) { return new Promise((ok) => { let b = ''; req.on('data', (c) => { b += c; if (b.length > 1e5) req.destroy(); }); req.on('end', () => { try { ok(JSON.parse(b || '{}')); } catch { ok({}); } }); }); }

createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const p = decodeURIComponent(url.pathname);
  // ---- mock API (local only)
  if (p === '/api/csrf-token') return send(res, 200, JSON.stringify({ csrfToken: 'preview-token' }), types['.json']);
  if (p.startsWith('/api/')) {
    const body = await readBody(req);
    if (req.headers['x-csrf-token'] !== 'preview-token') return send(res, 403, JSON.stringify({ success: false, message: 'Invalid CSRF token (preview)' }), types['.json']);
    if (p === '/api/contact') return send(res, 200, JSON.stringify({ success: true, message: 'preview: not sent' }), types['.json']);
    if (p === '/api/checkout') return send(res, 200, JSON.stringify({ success: false, message: `Preview mode: checkout not started (amount ${body.amount}, plan ${body.planKey}).` }), types['.json']);
    return send(res, 204, '', types['.json']);
  }
  // ---- live app routes (explained, not 404)
  if (APP_ROUTE.test(p)) return send(res, 200, appRoutePage(p), types['.html']);
  // ---- static
  let file = normalize(join(dist, p));
  if (!file.startsWith(dist)) return send(res, 400, 'bad path', types['.txt']);
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  if (!existsSync(file) && existsSync(file + '.html')) file += '.html';
  if (!existsSync(file)) return send(res, 404, readFileSync(join(dist, '404.html')), types['.html']);
  send(res, 200, readFileSync(file), types[extname(file)] || 'application/octet-stream');
}).listen(PORT, '127.0.0.1', () => console.log(`Preview: http://127.0.0.1:${PORT}  (drafts under /_drafts/)`));
