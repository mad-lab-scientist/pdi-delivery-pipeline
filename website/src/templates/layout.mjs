// Shared layout: <head>, header, footer and small UI helpers.
// Every dynamic string goes through e() (HTML escape). Raw HTML only comes from these templates.
import { site } from '../content/site.mjs';
import { services } from '../content/services.mjs';

export const e = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

export const nav = [
  { href: '/services', label: 'Services' },
  { href: '/pricing', label: 'Pricing' },
  { href: '/defense', label: 'Defense & CMMC' },
  { href: '/government', label: 'Government' },
  { href: '/about', label: 'About' },
  { href: '/contact', label: 'Contact' },
];

export function logoMark(id) {
  return `<svg class="logo-mark" viewBox="0 0 32 32" width="32" height="32" aria-hidden="true" focusable="false">
  <defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#4ade80"/></linearGradient></defs>
  <path d="M16 2.5 27.5 7v8.2c0 7.1-4.9 12.6-11.5 14.3C9.4 27.8 4.5 22.3 4.5 15.2V7Z" fill="rgba(34,211,238,.06)" stroke="url(#${id})" stroke-width="1.8" stroke-linejoin="round"/>
  <path d="m10.5 12 4 4-4 4" fill="none" stroke="url(#${id})" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M16.5 20.5h5.5" stroke="#4ade80" stroke-width="2.2" stroke-linecap="round"/>
</svg>`;
}

export const arrow = '<svg class="ico" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false"><path d="M3 8h9M8.5 4.5 12 8l-3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
export const check = '<svg class="ico ico-check" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false"><path d="m3.5 8.5 3 3 6-7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
export const cross = '<svg class="ico ico-cross" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false"><path d="m4.5 4.5 7 7m0-7-7 7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';

export const eyebrow = (index, label) => `<p class="eyebrow"><span class="eyebrow-prompt">&gt;_</span> ${index ? `<span class="eyebrow-index">${e(index)}</span> ` : ''}${e(label)}</p>`;

export function sectionHead(index, label, title, lead) {
  return `<header class="section-head">${eyebrow(index, label)}<h2>${title}</h2>${lead ? `<p class="lead">${e(lead)}</p>` : ''}</header>`;
}

export function pageHero({ crumbs = [], index, label, title, lead, aside = '' }) {
  const bc = crumbs.length
    ? `<nav class="breadcrumb" aria-label="Breadcrumb"><ol><li><a href="/">Home</a></li>${crumbs.map((c, i) => i === crumbs.length - 1 ? `<li aria-current="page">${e(c.label)}</li>` : `<li><a href="${e(c.href)}">${e(c.label)}</a></li>`).join('')}</ol></nav>`
    : '';
  return `<section class="page-hero">
  <div class="container page-hero-grid${aside ? ' has-aside' : ''}">
    <div class="page-hero-copy">${bc}${eyebrow(index, label)}<h1>${title}</h1>${lead ? `<p class="lead">${e(lead)}</p>` : ''}</div>
    ${aside ? `<div class="page-hero-aside">${aside}</div>` : ''}
  </div>
</section>`;
}

export function ctaBand(title = 'Start with a free assessment.', text = 'Tell us what you’re running and what keeps you up at night. You’ll get a plain-English findings report and an honest recommendation, even if that recommendation is “you’re fine.”') {
  return `<section class="cta-band" aria-labelledby="cta-title">
  <div class="container cta-band-inner">
    <div><h2 id="cta-title">${e(title)}</h2><p>${e(text)}</p></div>
    <div class="cta-actions"><a class="btn btn-primary" href="/contact" data-track-event="cta_click" data-track-label="cta-band-assessment">Get a free assessment ${arrow}</a><a class="btn btn-ghost" href="${e(site.phoneHref)}">${e(site.phone)}</a></div>
  </div>
</section>`;
}

function header(currentPath) {
  const links = nav.map((n) => {
    const active = currentPath === n.href || (n.href !== '/' && currentPath.startsWith(n.href + '/'));
    return `<li><a href="${n.href}"${active ? ' aria-current="page"' : ''}>${e(n.label)}</a></li>`;
  }).join('');
  return `<header class="site-header" data-header>
  <div class="container header-inner">
    <a class="brand" href="/" aria-label="${e(site.brand)} home">${logoMark('lg-h')}<span class="brand-text"><span class="brand-name">PEARSON<span class="brand-sep">/</span>CYBER DEFENSE</span><span class="brand-sub">Pearson Digital Infrastructure LLC</span></span></a>
    <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-nav" data-nav-toggle><span class="nav-toggle-bars" aria-hidden="true"></span><span class="sr-only">Menu</span></button>
    <nav class="site-nav" id="site-nav" aria-label="Primary" data-nav>
      <ul class="nav-links">${links}</ul>
      <div class="nav-actions"><a class="nav-login" href="/login">Client login</a><a class="btn btn-primary btn-sm" href="/contact" data-track-event="cta_click" data-track-label="header-assessment">Free assessment</a></div>
    </nav>
  </div>
</header>`;
}

function footer({ legalLinks = [] }) {
  const svc = services.map((s) => `<li><a href="/services/${s.slug}">${e(s.name)}</a></li>`).join('');
  const year = new Date().getFullYear();
  return `<footer class="site-footer">
  <div class="container footer-grid">
    <div class="footer-brand">
      <a class="brand" href="/" aria-label="${e(site.brand)} home">${logoMark('lg-f')}<span class="brand-text"><span class="brand-name">PEARSON<span class="brand-sep">/</span>CYBER DEFENSE</span><span class="brand-sub">${e(site.legalName)}</span></span></a>
      <p>${e(site.tagline)} Network, virtualization, cloud, DevOps, security and private AI from Huntsville, Alabama.</p>
      <ul class="badge-row" aria-label="Readiness focus">${site.readinessBadges.map((b) => `<li class="badge">${e(b)}</li>`).join('')}</ul>
      <p class="fineprint">Readiness and alignment claims, not certifications. PDI does not certify anyone.</p>
    </div>
    <div class="footer-col"><h3>Services</h3><ul class="footer-services">${svc}</ul></div>
    <div class="footer-col"><h3>Company</h3><ul>
      <li><a href="/about">About</a></li><li><a href="/engineering">Engineering</a></li><li><a href="/pricing">Pricing &amp; rates</a></li><li><a href="/service-levels">Service levels</a></li>
      <li><a href="/defense">Defense &amp; CMMC</a></li><li><a href="/government">Government</a></li><li><a href="/payments">Pay an invoice</a></li>
      <li><a href="/contact">Contact</a></li><li><a href="/login">Client login</a></li>
      ${legalLinks.map((l) => `<li><a href="${e(l.href)}">${e(l.label)}</a></li>`).join('')}
    </ul></div>
    <div class="footer-col"><h3>Contact</h3>
      <address>
        <a href="${e(site.phoneHref)}">${e(site.phone)}</a><br>
        <a href="mailto:${e(site.email)}">${e(site.email)}</a><br>
        <span class="muted">${e(site.address.label)}</span><br>
        ${e(site.address.street)}<br>${e(site.address.city)}, ${e(site.address.region)} ${e(site.address.postal)}
      </address>
      <p class="muted small">${e(site.businessHours)}. P1 emergencies: call.</p>
    </div>
  </div>
  <div class="container footer-bottom">
    <p>© ${year} ${e(site.legalName)} ${e(site.dba)}. All rights reserved.</p>
    <p class="mono small"><span class="status-dot" aria-hidden="true"></span> built from source · no fake stats · published rates</p>
  </div>
</footer>`;
}

export function layout({ path, title, description, body, scripts = [], jsonLd = null, noindex = false, legalLinks = [], assets, bodyClass = '' }) {
  const fullTitle = path === '/' ? `${site.brand} | Cybersecurity & IT, Huntsville AL` : `${title} | ${site.brand}`;
  const canonical = site.url + (path === '/' ? '/' : path);
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${e(fullTitle)}</title>
<meta name="description" content="${e(description)}">
<link rel="canonical" href="${e(canonical)}">
<meta name="robots" content="${noindex ? 'noindex, nofollow' : 'index, follow, max-image-preview:large'}">
<meta name="theme-color" content="#05070d">
<meta name="csrf-token" content="">
<meta property="og:type" content="website">
<meta property="og:site_name" content="${e(site.brand)}">
<meta property="og:title" content="${e(fullTitle)}">
<meta property="og:description" content="${e(description)}">
<meta property="og:url" content="${e(canonical)}">
<meta property="og:image" content="${e(site.url)}/images/brand/pearson-digital-infrastructure-hero-panel-2400x1300.png">
<meta property="og:locale" content="en_US">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="${assets['img/favicon.svg']}" type="image/svg+xml">
<link rel="apple-touch-icon" href="/icons/app-icon-180.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&amp;family=JetBrains+Mono:wght@400;500;600&amp;family=Space+Grotesk:wght@500;600;700&amp;display=swap">
<link rel="stylesheet" href="${assets['css/site.css']}">
${jsonLd ? `<script type="application/ld+json">${JSON.stringify(jsonLd).replace(/</g, '\\u003c')}</script>` : ''}
</head>
<body class="${e(bodyClass)}">
<a class="skip-link" href="#main">Skip to content</a>
${header(path)}
<main id="main">
${body}
</main>
${footer({ legalLinks })}
<script src="${assets['js/site.js']}" defer></script>
${scripts.map((s) => `<script src="${assets[s]}" defer></script>`).join('\n')}
</body>
</html>
`;
}
