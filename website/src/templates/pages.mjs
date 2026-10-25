// Page bodies. Each export returns { path, title, description, body, ...layoutOptions }.
import { e, eyebrow, sectionHead, pageHero, ctaBand, arrow, check, cross } from './layout.mjs';
import { site, principles, delivery, lab, techStack } from '../content/site.mjs';
import { services, layers, serviceBySlug } from '../content/services.mjs';
import { tiers, tierById, serviceRates, premiums, blocks, blockExample, projects, marketRefs, rateCard, money } from '../content/pricing.mjs';
import { sla } from '../content/sla.mjs';
import { cmmc } from '../content/defense.mjs';
import { legalDocs, approved as legalApproved, effectiveDate as legalEffective } from '../content/legal.mjs';
import { stages as pipelineStages, controls as nistControls, evidence as controlEvidence, loadRuns } from '../content/pipeline.mjs';

// ---------------------------------------------------------------- shared components
const businessTiers = tiers.filter((t) => !t.id.startsWith('res'));

function rateChips(slug) {
  const rows = serviceRates[slug] || [];
  return rows.map(([id, label]) => `<li><span>${e(label)}</span><strong>${money(tierById[id].rate)}<small>/h</small></strong></li>`).join('');
}

function serviceCard(s) {
  const layer = layers.find((l) => l.id === s.layer);
  return `<a class="card svc-card" href="/services/${s.slug}">
  <span class="svc-top"><span class="code">${e(s.code)}</span><span class="layer-tag">${e(layer.id)} · ${e(layer.name)}</span></span>
  <h3>${e(s.name)}</h3>
  <p>${e(s.summary)}</p>
  <span class="link-more">Explore ${arrow}</span>
</a>`;
}

function terminal() {
  const lines = [
    ['cmd', '$ pdi assess --scope network,identity,backup,cloud'],
    ['out', '[scan] perimeter ...... firewall policy and VPN review'],
    ['out', '[scan] identity ....... MFA coverage and admin separation'],
    ['out', '[scan] backups ........ restore test, not just a schedule'],
    ['out', '[scan] cloud .......... Microsoft 365 tenant hardening'],
    ['ok', '[plan] assess → stabilize → modernize → operate'],
    ['ok', '✓ report: owner-level, plain English'],
  ];
  return `<div class="terminal" data-terminal aria-label="Example assessment session" role="img">
  <div class="terminal-bar"><span></span><span></span><span></span><p class="mono">admin@mrpearson.net: ~</p></div>
  <ol class="terminal-body">${lines.map(([k, t]) => `<li class="t-${k}">${e(t)}</li>`).join('')}<li class="t-cursor" aria-hidden="true">$ <span class="cursor"></span></li></ol>
</div>`;
}

function contactForm(sourcePage) {
  const options = services.map((s) => `<option value="${e(s.name)}">${e(s.name)}</option>`).join('');
  return `<form class="form card" data-contact-form data-source-page="${e(sourcePage)}" novalidate>
  <div class="form-grid">
    <div class="field"><label for="cf-name">Name <span aria-hidden="true">*</span></label><input id="cf-name" name="name" type="text" autocomplete="name" required maxlength="120"></div>
    <div class="field"><label for="cf-email">Email <span aria-hidden="true">*</span></label><input id="cf-email" name="email" type="email" autocomplete="email" required maxlength="160"></div>
    <div class="field"><label for="cf-company">Company or household</label><input id="cf-company" name="company" type="text" autocomplete="organization" maxlength="160"></div>
    <div class="field"><label for="cf-service">What do you need?</label><select id="cf-service" name="service"><option value="">Choose a service</option>${options}<option value="Full managed IT">Full managed IT</option><option value="Not sure yet">Not sure yet</option></select></div>
    <div class="field field-full"><label for="cf-message">What’s going on? <span aria-hidden="true">*</span></label><textarea id="cf-message" name="message" rows="5" required maxlength="4000" placeholder="Your environment, the problem, and any deadline (an audit, a contract award, a renewal)…"></textarea></div>
  </div>
  <div class="form-foot">
    <button class="btn btn-primary" type="submit">Send request ${arrow}</button>
    <p class="muted small">We reply within 1 business day. Emergency for an existing client? Call <a href="${e(site.phoneHref)}">${e(site.phone)}</a>.</p>
  </div>
  <p class="form-status" role="status" aria-live="polite"></p>
</form>`;
}

function slaTiles() {
  return `<ul class="sla-tiles">${sla.priorities.map((p) => `<li class="sla-tile sla-${p.p.toLowerCase()}"><span class="mono">${e(p.p)} · ${e(p.name)}</span><strong>${e(p.response)}</strong><small>${e(p.definition)}</small></li>`).join('')}</ul>`;
}

function countdown() {
  return `<div class="countdown" data-countdown="${e(cmmc.phase2.iso)}">
  <p class="mono countdown-label">CMMC Phase 2 begins ${e(cmmc.phase2.label)}</p>
  <p class="countdown-value"><span data-countdown-days>Nov 10</span> <span class="countdown-unit" data-countdown-unit>2026</span></p>
  <p class="small muted" data-countdown-note>Level 2 C3PAO certification in applicable DoD solicitations.</p>
</div>`;
}

function faqList(faqs) {
  return `<div class="faq">${faqs.map((f) => `<details><summary>${e(f.q)}</summary><p>${e(f.a)}</p></details>`).join('')}</div>`;
}

export const orgJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'ProfessionalService',
  name: site.brand,
  legalName: site.legalName,
  url: site.url,
  telephone: '+1-256-675-9961',
  email: site.email,
  slogan: site.tagline,
  address: { '@type': 'PostalAddress', streetAddress: site.address.street, addressLocality: site.address.city, addressRegion: site.address.region, postalCode: site.address.postal, addressCountry: site.address.country },
  areaServed: [...site.serviceArea.primary, 'North Alabama', 'United States'],
  openingHoursSpecification: [{ '@type': 'OpeningHoursSpecification', dayOfWeek: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'], opens: '08:00', closes: '18:00' }],
  knowsAbout: ['Cybersecurity', 'Network security', 'Fortinet', 'Proxmox VE', 'CMMC readiness', 'NIST SP 800-171', 'DevOps', 'Private AI'],
};

// ---------------------------------------------------------------- home
export function home() {
  const stack = `<div class="stack" data-stack>
    <ol class="stack-layers" role="list">${layers.map((l, i) => `<li><button class="stack-layer${i === 0 ? ' is-active' : ''}" type="button" aria-expanded="${i === 0}" aria-controls="layer-${l.id}" data-layer="${l.id}"><span class="mono">${e(l.id)}</span><span class="stack-name">${e(l.name)}</span><span class="stack-blurb">${e(l.blurb)}</span></button></li>`).join('')}</ol>
    <div class="stack-panels">${layers.map((l, i) => {
      const svcs = services.filter((s) => s.layer === l.id);
      return `<section class="stack-panel${i === 0 ? ' is-active' : ''}" id="layer-${l.id}" aria-label="${e(l.name)}"><p class="mono stack-panel-label">${e(l.id)} / ${e(l.name)}</p>${svcs.map((s) => `<a class="stack-svc" href="/services/${s.slug}"><span class="code">${e(s.code)}</span><span><strong>${e(s.name)}</strong><span>${e(s.outcomes[0])}</span></span>${arrow}</a>`).join('')}</section>`;
    }).join('')}</div>
  </div>`;

  const body = `
<section class="hero">
  <canvas class="hero-canvas" data-network aria-hidden="true"></canvas>
  <div class="hero-fade" aria-hidden="true"></div>
  <div class="container hero-grid">
    <div class="hero-copy">
      ${eyebrow('', 'Huntsville, AL · Architect-led infrastructure & security')}
      <h1>Cyber defense and digital infrastructure <span class="grad-text">built for serious business.</span></h1>
      <p class="lead">Network, virtualization, cloud, DevOps, security and private AI, designed, built and supported by the architect who owns the outcome. Not a sales team.</p>
      <div class="hero-actions"><a class="btn btn-primary btn-lg" href="/contact" data-track-event="cta_click" data-track-label="hero-assessment">Get a free assessment ${arrow}</a><a class="btn btn-ghost btn-lg" href="/pricing">See published rates</a></div>
      <ul class="hero-meta" aria-label="At a glance">
        <li><span class="status-dot" aria-hidden="true"></span>Published hourly rates</li>
        <li><span class="status-dot" aria-hidden="true"></span>P1 response: 1 business hour</li>
        <li><span class="status-dot" aria-hidden="true"></span>CMMC & NIST SP 800-171 readiness</li>
      </ul>
    </div>
    <div class="hero-side">${terminal()}</div>
  </div>
</section>

<section class="proofbar" aria-label="Readiness focus">
  <div class="container proofbar-inner">
    <p class="mono small">Readiness focus</p>
    <ul class="badge-row">${site.readinessBadges.map((b) => `<li class="badge">${e(b)}</li>`).join('')}</ul>
    <p class="small muted">Readiness, not certification. We’ll tell you exactly what that means.</p>
  </div>
</section>

<section class="section" id="stack">
  <div class="container">
    ${sectionHead('01', 'The stack', 'Seven layers. <span class="grad-text">One architect</span> who understands all of them.', 'Most problems live between layers: the firewall rule nobody documented, the backup that never restored, the cloud tenant without MFA. PDI works the whole stack, so nothing falls through the seams.')}
    ${stack}
  </div>
</section>

<section class="section section-alt" id="services">
  <div class="container">
    ${sectionHead('02', 'Services', 'Thirteen service lines, <span class="grad-text">one operating model.</span>', 'Start with the problem in front of you. Grow into the rest when it makes sense.')}
    <div class="card-grid">${services.map(serviceCard).join('')}</div>
  </div>
</section>

<section class="section" id="how">
  <div class="container">
    ${sectionHead('03', 'Delivery model', 'Assess → Stabilize → Modernize → <span class="grad-text">Operate.</span>', 'Simple enough to understand in a handshake. Serious enough to defend real business operations.')}
    <ol class="steps">${delivery.map((d, i) => `<li class="step"><span class="step-n mono">0${i + 1}</span><h3>${e(d.step)}</h3><p>${e(d.text)}</p></li>`).join('')}</ol>
  </div>
</section>

<section class="section section-alt" id="rates">
  <div class="container split">
    <div>
      ${sectionHead('04', 'Published rates', 'No mystery pricing. <span class="grad-text">The rates are on the page.</span>', 'Hourly rates benchmarked against Huntsville wage data and published market ranges. Monthly managed plans and hosting are quoted from a real cost-to-serve assessment, never from a guess.')}
      <div class="btn-row"><a class="btn btn-primary" href="/pricing">Full rate card ${arrow}</a><a class="btn btn-ghost" href="/pricing#market">How we set rates</a></div>
    </div>
    <div class="card rate-mini">
      <p class="mono rate-mini-head">$ pdi rates --business-hours</p>
      <ul>${businessTiers.map((t) => `<li><span>${e(t.name)}</span><strong>${money(t.rate)}<small>/h</small></strong></li>`).join('')}</ul>
      <p class="small muted">Residential: ${money(tierById['res-remote'].rate)}/h remote, ${money(tierById['res-onsite'].rate)}/h on-site. Prepaid blocks save up to 15%.</p>
    </div>
  </div>
</section>

<section class="section" id="sla">
  <div class="container">
    ${sectionHead('05', 'Service levels', 'Promises one engineer can keep. <span class="grad-text">Every time.</span>', 'Response targets for business hours (Monday–Friday, 8–6 Central). After hours, P1 emergencies are handled by phone on a best-effort basis.')}
    ${slaTiles()}
    <p class="callout"><strong>Straight talk:</strong> ${e(sla.no247)} <a href="/service-levels">Read the full service levels ${arrow}</a></p>
  </div>
</section>

<section class="section section-alt" id="defense">
  <div class="container split split-center">
    <div>
      ${sectionHead('06', 'Defense industrial base', 'CMMC Phase 2: <span class="grad-text">November 10, 2026.</span>', 'From November 10, 2026, applicable DoD solicitations can require Level 2 certification by a C3PAO at award. We shrink your CUI scope, close the highest-weight gaps first and run the evidence program that backs your affirmation.')}
      <div class="btn-row"><a class="btn btn-primary" href="/defense">CMMC readiness ${arrow}</a><a class="btn btn-ghost" href="/government">Government contracting</a></div>
    </div>
    <div class="card defense-card">${countdown()}<ul class="fact-list">${cmmc.facts.slice(0, 3).map((f) => `<li><strong>${e(f.k)}</strong><span>${e(f.v)}</span></li>`).join('')}</ul></div>
  </div>
</section>

<section class="section" id="lab">
  <div class="container">
    ${sectionHead('07', 'Proof, not promises', 'We run what we sell.', 'PDI’s own infrastructure is the reference build: designed, operated and documented the same way we’ll run yours.')}
    <div class="lab-grid">${lab.map((x) => `<div class="card lab-card"><span class="code">${e(x.code)}</span><h3>${e(x.title)}</h3><p>${e(x.text)}</p></div>`).join('')}</div>
    <ul class="chip-row" aria-label="Platforms we work with">${techStack.map((t) => `<li class="chip">${e(t)}</li>`).join('')}</ul>
  </div>
</section>

<section class="section section-alt" id="contact">
  <div class="container split">
    <div>${sectionHead('08', 'Start the conversation', 'Get a free assessment.', 'Tell us what you’re running and what you’re worried about. You’ll get a plain-English findings report and an honest recommendation.')}
      <ul class="contact-list"><li><span class="mono">phone</span><a href="${e(site.phoneHref)}">${e(site.phone)}</a></li><li><span class="mono">email</span><a href="mailto:${e(site.email)}">${e(site.email)}</a></li><li><span class="mono">hours</span><span>${e(site.businessHours)}</span></li></ul>
    </div>
    ${contactForm('homepage')}
  </div>
</section>`;
  return { path: '/', title: 'Home', description: 'Architect-led cybersecurity, network, virtualization, cloud, DevOps and private AI in Huntsville, AL, with published hourly rates and honest service levels.', body, scripts: ['js/network.js'], jsonLd: orgJsonLd, bodyClass: 'page-home' };
}

// ---------------------------------------------------------------- services
export function servicesIndex() {
  const body = `${pageHero({ crumbs: [{ label: 'Services' }], index: '', label: 'Services', title: 'Every layer of your stack, <span class="grad-text">one accountable architect.</span>', lead: 'Thirteen service lines organized by the layer they protect. Each page lists what’s included, what isn’t, and the rate that applies.' })}
<section class="section">
  <div class="container">${layers.map((l) => {
    const svcs = services.filter((s) => s.layer === l.id);
    return `<div class="layer-group"><header class="layer-head"><span class="mono">${e(l.id)}</span><h2>${e(l.name)}</h2><p class="muted">${e(l.blurb)}</p></header><div class="card-grid">${svcs.map(serviceCard).join('')}</div></div>`;
  }).join('')}</div>
</section>
${ctaBand()}`;
  return { path: '/services', title: 'Services', description: 'Cybersecurity, network, virtualization, cloud, DevOps, SOC monitoring, compliance readiness, backup, private AI and help desk from Pearson Cyber Defense.', body };
}

export function servicePage(s) {
  const layer = layers.find((l) => l.id === s.layer);
  const isVps = s.slug === 'vps-hosting';
  const aside = `<div class="card rate-card-aside">
    <p class="mono">$ pdi rate --service ${e(s.code.toLowerCase())}</p>
    ${isVps ? '<p class="aside-note">Hosting is priced monthly per workload and quoted after scoping.</p>' : ''}
    <ul class="rate-chips">${rateChips(s.slug)}</ul>
    <p class="small muted">Business-hours rates. After-hours premiums and minimums are on the <a href="/pricing#premiums">pricing page</a>.</p>
    <a class="btn btn-primary btn-block" href="/contact" data-track-event="cta_click" data-track-label="service-${e(s.slug)}">Request an assessment ${arrow}</a>
  </div>`;
  const related = s.related.map((r) => serviceBySlug[r]).filter(Boolean);
  const body = `${pageHero({ crumbs: [{ href: '/services', label: 'Services' }, { label: s.name }], index: s.code, label: `${layer.id} · ${layer.name}`, title: e(s.name), lead: s.summary, aside })}
<section class="section section-tight">
  <div class="container">
    <ul class="outcomes">${s.outcomes.map((o) => `<li>${check}<span>${e(o)}</span></li>`).join('')}</ul>
  </div>
</section>
<section class="section section-alt">
  <div class="container split split-top">
    <div>${sectionHead('01', 'Capabilities', 'What we do')}<ul class="check-list">${s.capabilities.map((c) => `<li>${check}<span>${e(c)}</span></li>`).join('')}</ul></div>
    <div>${sectionHead('02', 'Deliverables', 'What you get')}<ul class="deliverables">${s.deliverables.map((d, i) => `<li><span class="mono">${String(i + 1).padStart(2, '0')}</span>${e(d)}</li>`).join('')}</ul>
      <p class="mono small tools-label">stack</p><ul class="chip-row">${s.tools.map((t) => `<li class="chip">${e(t)}</li>`).join('')}</ul></div>
  </div>
</section>
<section class="section">
  <div class="container split split-top">
    <div>${sectionHead('03', 'Fit', 'Honest scoping')}
      <div class="fit"><div class="fit-col fit-good"><h3>Good fit</h3><ul>${s.fit.good.map((g) => `<li>${check}<span>${e(g)}</span></li>`).join('')}</ul></div>
      <div class="fit-col fit-not"><h3>Not a fit</h3><ul>${s.fit.not.map((g) => `<li>${cross}<span>${e(g)}</span></li>`).join('')}</ul></div></div>
    </div>
    <div>${sectionHead('04', 'FAQ', 'Questions we hear')}${faqList(s.faqs)}</div>
  </div>
</section>
<section class="section section-alt">
  <div class="container">${sectionHead('05', 'Related', 'Works well with')}<div class="card-grid card-grid-3">${related.map(serviceCard).join('')}</div></div>
</section>
${ctaBand()}`;
  return { path: `/services/${s.slug}`, title: s.title, description: s.description, body };
}

// ---------------------------------------------------------------- pricing
export function pricing() {
  const ex = blocks.sizes.map((b) => blockExample(b.hours, b.discount));
  const svcRows = services.map((s) => `<tr><th scope="row"><a href="/services/${s.slug}">${e(s.name)}</a></th><td>${(serviceRates[s.slug] || []).map(([id, label]) => `<span class="rate-pill">${e(label)}: <strong>${money(tierById[id].rate)}/h</strong></span>`).join(' ')}${s.slug === 'vps-hosting' ? ' <span class="muted small">(hosting itself is priced monthly per workload)</span>' : ''}</td></tr>`).join('');
  const body = `${pageHero({ crumbs: [{ label: 'Pricing' }], index: '', label: `Labor Rate Card v${rateCard.version} · adopted ${rateCard.adopted}`, title: 'Published rates. <span class="grad-text">Real math.</span>', lead: 'Every hourly rate PDI charges is on this page, along with the premiums, minimums and discounts. No contracts with fine print, no hidden fees, no surprise invoices.' })}
<section class="section section-tight">
  <div class="container">
    <div class="table-wrap card">
      <table class="rate-table">
        <caption class="sr-only">PDI Labor Rate Card, business hours, USD per hour</caption>
        <thead><tr><th scope="col">Labor tier</th><th scope="col">Typical work</th><th scope="col" class="num">Rate</th></tr></thead>
        <tbody>${tiers.map((t) => `<tr><th scope="row">${e(t.name)}</th><td>${e(t.work)}</td><td class="num"><strong>${money(t.rate)}</strong><small>/h</small></td></tr>`).join('')}</tbody>
      </table>
    </div>
    <p class="small muted table-note">${e(rateCard.basis)}</p>
  </div>
</section>
<section class="section section-alt" id="by-service">
  <div class="container">${sectionHead('01', 'By service', 'Which rate applies', 'You pay for the work, not the person. When T1 work gets done, it’s billed at T1.')}
    <div class="table-wrap card"><table class="rate-table rate-table-services"><caption class="sr-only">Applicable rates by service line</caption><thead><tr><th scope="col">Service line</th><th scope="col">Rate(s)</th></tr></thead><tbody>${svcRows}</tbody></table></div>
  </div>
</section>
<section class="section" id="premiums">
  <div class="container split split-top">
    <div>${sectionHead('02', 'Premiums & minimums', 'After hours, travel and minimums')}
      <div class="table-wrap card"><table class="rate-table"><caption class="sr-only">Premiums, minimums and travel</caption><tbody>${premiums.map((p) => `<tr><th scope="row">${e(p.rule)}</th><td>${e(p.policy)}</td></tr>`).join('')}</tbody></table></div>
    </div>
    <div id="blocks">${sectionHead('03', 'Prepaid block hours', 'Buy time ahead. Save up to 15%.')}
      <p>Prepaid blocks are dollar-value balances drawn down at the rate of the work performed. They expire after ${blocks.expiryMonths} months.</p>
      <div class="block-cards">${ex.map((x) => `<div class="card block-card"><p class="mono">${x.hours}-hour block · ${Math.round(x.discount * 100)}% off</p><p class="block-price">${money(x.price)}</p><p class="small muted">Example at the ${e(x.tier.name)} rate: ${money(x.list)} of work (${x.hours} × ${money(x.tier.rate)}) for ${money(x.price)}. You save ${money(x.saved)}.</p></div>`).join('')}</div>
    </div>
  </div>
</section>
<section class="section section-alt">
  <div class="container split split-top">
    <div>${sectionHead('04', 'Projects', 'Fixed-fee projects')}<p>${e(projects.method)} You approve a written scope and price before work starts.</p></div>
    <div>${sectionHead('05', 'Managed plans & hosting', 'Quoted from cost-to-serve')}
      <p>Monthly managed IT plans are priced per user or device from a real cost-to-serve assessment of your tools, endpoints and support needs. They’re not hourly rate × hours. VPS and application hosting are priced monthly per workload. Both are quoted after a free assessment, so the number is right the first time.</p>
      <p class="small muted">Federal work is priced per solicitation and isn’t quoted from this commercial card.</p>
    </div>
  </div>
</section>
<section class="section" id="market">
  <div class="container">${sectionHead('06', 'How we set rates', 'Check our numbers yourself.', 'Rates are benchmarked against Huntsville wage data (BLS Occupational Employment and Wage Statistics, May 2025) and these published market ranges. Each PDI rate sits inside its range.')}
    <div class="table-wrap card"><table class="rate-table"><caption class="sr-only">Published market references</caption><thead><tr><th scope="col">Source</th><th scope="col">Published range</th></tr></thead><tbody>${marketRefs.map((m) => `<tr><th scope="row"><a href="${e(m.url)}" rel="noopener" target="_blank">${e(m.source)}</a></th><td>${e(m.figure)}</td></tr>`).join('')}</tbody></table></div>
  </div>
</section>
<section class="section section-alt">
  <div class="container narrow">${sectionHead('07', 'FAQ', 'Billing questions')}${faqList([
    { q: 'How is time billed?', a: 'Remote work is billed in 15-minute increments with a 30-minute minimum. Scheduled on-site work has a 1-hour minimum. Emergency on-site dispatch and holidays are 2× with a 2-hour minimum.' },
    { q: 'Is the initial assessment really free?', a: 'Yes. The initial assessment carries no commitment. You get findings and recommendations in plain English, and you decide what, if anything, happens next.' },
    { q: 'How do I pay?', a: 'PDI invoices after work or per your agreement. Invoices can be paid online through secure Stripe Checkout on the payments page.' },
    { q: 'Do you discount?', a: 'Prepaid blocks save 10% (20-hour) or 15% (40-hour). Other discounts are rare and approved case by case. We’d rather price honestly than pad rates to discount them later.' },
  ])}</div>
</section>
${ctaBand('Get an exact quote.', 'Every engagement starts with a free assessment, so your quote is based on your environment, not a template.')}`;
  return { path: '/pricing', title: 'Pricing & Hourly Rates', description: 'PDI’s published hourly rates: T1 $125, T2 $175, T3 $225, security $225, incident response and compliance $275, plus premiums, minimums and prepaid blocks.', body };
}

// ---------------------------------------------------------------- service levels
export function serviceLevels() {
  const body = `${pageHero({ crumbs: [{ label: 'Service levels' }], index: '', label: `SLA v${sla.version} · adopted ${sla.adopted}`, title: 'Service levels <span class="grad-text">you can hold us to.</span>', lead: 'Promise only what one accountable engineer can deliver every time, then beat it. These are the commitments, written plainly.' })}
<section class="section section-tight"><div class="container">${slaTiles()}<p class="callout"><strong>No 24/7 claims.</strong> ${e(sla.no247)}</p></div></section>
<section class="section section-alt"><div class="container">${sectionHead('01', 'Response targets', 'By priority')}
  <div class="table-wrap card"><table class="rate-table"><caption class="sr-only">Response targets by priority (business hours)</caption><thead><tr><th scope="col">Priority</th><th scope="col">Definition</th><th scope="col">Response</th><th scope="col">Status updates</th><th scope="col">Restore target (goal)</th></tr></thead>
  <tbody>${sla.priorities.map((p) => `<tr><th scope="row">${e(p.p)} ${e(p.name)}</th><td>${e(p.definition)}</td><td><strong>${e(p.response)}</strong></td><td>${e(p.updates)}</td><td>${e(p.restore)}</td></tr>`).join('')}</tbody></table></div>
  <p class="small muted table-note">${e(sla.responseMeaning)}</p>
</div></section>
<section class="section"><div class="container split split-top">
  <div>${sectionHead('02', 'Coverage', 'When and how to reach us')}<div class="table-wrap card"><table class="rate-table"><caption class="sr-only">Coverage</caption><tbody>${sla.coverage.map((c) => `<tr><th scope="row">${e(c.item)}</th><td>${e(c.value)}</td></tr>`).join('')}</tbody></table></div></div>
  <div>${sectionHead('03', 'Security incidents', 'When it’s a breach')}<ul class="check-list">${sla.security.map((x) => `<li>${check}<span>${e(x)}</span></li>`).join('')}</ul>
    ${sectionHead('04', 'Maintenance', 'Change windows')}<p>${e(sla.maintenance)}</p></div>
</div></section>
<section class="section section-alt"><div class="container split split-top">
  <div>${sectionHead('05', 'Continuity', 'No single point of failure')}<ul class="check-list">${sla.continuity.map((x) => `<li>${check}<span>${e(x)}</span></li>`).join('')}</ul></div>
  <div>${sectionHead('06', 'Measurement', 'How we keep score')}<p>${e(sla.measurement)}</p>${sectionHead('07', 'Exclusions', 'What’s outside the SLA')}<p>${e(sla.exclusions)}</p></div>
</div></section>
${ctaBand()}`;
  return { path: '/service-levels', title: 'Service Levels (SLA v2.0)', description: 'PDI service levels: P1 response in 1 business hour, P2 in 4, P3 next business day, P4 in 2 business days. Business hours Monday–Friday, 8–6 Central.', body };
}

// ---------------------------------------------------------------- defense
export function defense() {
  const body = `${pageHero({ crumbs: [{ label: 'Defense & CMMC' }], index: '', label: `CMMC 2.0 · facts as of ${cmmc.asOf}`, title: 'CMMC readiness <span class="grad-text">for the Huntsville defense industrial base.</span>', lead: 'Shrink your CUI scope, close the highest-weight gaps first, and run the evidence program that backs your affirmation. Readiness, not certification, from a firm that knows the difference.', aside: `<div class="card defense-card">${countdown()}</div>` })}
<section class="section section-tight"><div class="container"><ul class="fact-grid">${cmmc.facts.map((f) => `<li class="card"><strong>${e(f.k)}</strong><span>${e(f.v)}</span></li>`).join('')}</ul></div></section>
<section class="section section-alt"><div class="container">${sectionHead('01', 'Levels', 'What each level requires')}
  <div class="table-wrap card"><table class="rate-table"><caption class="sr-only">CMMC levels</caption><thead><tr><th scope="col">Level</th><th scope="col">Protects</th><th scope="col">Requirements</th><th scope="col">Assessment</th></tr></thead><tbody>${cmmc.levels.map((l) => `<tr><th scope="row">${e(l.level)}</th><td>${e(l.protects)}</td><td>${e(l.requirements)}</td><td>${e(l.assessment)}</td></tr>`).join('')}</tbody></table></div>
</div></section>
<section class="section"><div class="container">${sectionHead('02', 'Phased rollout', 'Where the program stands')}
  <ol class="timeline">${cmmc.phases.map((p) => `<li class="timeline-item${p.n === 2 ? ' is-now' : ''}"><span class="mono">Phase ${p.n} · ${e(p.start)}</span><p>${e(p.what)}</p></li>`).join('')}</ol>
  <p class="small muted">DoD may include higher requirements earlier at its discretion. Sources: ${e(cmmc.sources)}. Verify current status before relying on any date.</p>
</div></section>
<section class="section section-alt"><div class="container">${sectionHead('03', 'Method', 'How a PDI readiness engagement runs')}
  <ol class="method">${cmmc.method.map((m, i) => `<li class="card"><span class="mono">${String(i).padStart(2, '0')} · ${e(m.time)}</span><h3>${e(m.stage)}</h3><p>${e(m.out)}</p></li>`).join('')}</ol>
</div></section>
<section class="section"><div class="container split split-top">
  <div>${sectionHead('04', 'Boundaries', 'What we don’t do')}<ul class="check-list">${cmmc.boundaries.map((b) => `<li>${check}<span>${e(b)}</span></li>`).join('')}</ul></div>
  <div>${sectionHead('05', 'Related services', 'Built for contractors')}<div class="stack-list">${['compliance-readiness-evidence', 'soc-monitoring-log-management', 'cybersecurity', 'backup-recovery'].map((sl) => { const s = serviceBySlug[sl]; return `<a class="stack-svc" href="/services/${s.slug}"><span class="code">${e(s.code)}</span><span><strong>${e(s.name)}</strong><span>${e(s.outcomes[0])}</span></span>${arrow}</a>`; }).join('')}</div>
    <p class="small muted">Compliance &amp; vCISO work is billed at ${money(tierById.grc.rate)}/h. See <a href="/pricing">pricing</a>.</p></div>
</div></section>
${ctaBand('Phase 2 is a calendar problem.', 'Assessor calendars book months out. Start the gap assessment now, so your evidence is ready before the award.')}`;
  return { path: '/defense', title: 'CMMC & NIST 800-171 Readiness', description: 'CMMC Level 2 readiness for defense contractors: scoping, 110-requirement gap assessment, SSP, POA&M and evidence programs. Phase 2 begins November 10, 2026.', body };
}

// ---------------------------------------------------------------- government
export function government() {
  const comps = [
    ['Network and perimeter security architecture', 'Fortinet FortiGate design, VLAN segmentation, VPN, firewall policy review'],
    ['Virtualization and infrastructure', 'Proxmox VE, Dell PowerEdge, Linux and Windows Server administration, backup and disaster recovery'],
    ['Security monitoring', 'Wazuh SIEM/XDR deployment and tuning, vulnerability scanning, incident response support'],
    ['Compliance readiness', 'NIST SP 800-171 and CMMC gap assessments, System Security Plans, POA&Ms, evidence programs'],
    ['Cloud and Microsoft 365', 'Tenant security, identity and MFA hardening, migrations'],
    ['Automation and private AI', 'On-premises AI where data stays on customer-controlled hardware; n8n workflow automation'],
  ];
  const diffs = [
    'Architect-led: the engineer who designs the solution delivers it.',
    'Local to the Huntsville defense community, with working knowledge of CUI, CMMC and DFARS requirements.',
    'Security-first operating model: least privilege, tested backups, documented runbooks.',
    'Private AI capability: automation without sending sensitive data to public AI services.',
  ];
  const body = `${pageHero({ crumbs: [{ label: 'Government' }], index: '', label: 'For contracting officers & prime contractors', title: 'Government <span class="grad-text">contracting.</span>', lead: 'A small, architect-led firm in Huntsville delivering network, infrastructure, security and compliance-readiness work for prime contractors and agencies.' })}
<section class="section section-tight"><div class="container split split-top">
  <div class="card id-card"><p class="mono">company data</p><dl>
    <div><dt>Legal name</dt><dd>${e(site.legalName)}</dd></div><div><dt>Doing business as</dt><dd>${e(site.brand)}</dd></div>
    <div><dt>Business size</dt><dd>Small business</dd></div><div><dt>Primary NAICS</dt><dd>541512 Computer Systems Design Services</dd></div>
    <div><dt>Location</dt><dd>${e(site.address.city)}, ${e(site.address.region)} (serves Redstone Arsenal, Cummings Research Park and North Alabama; remote nationwide)</dd></div>
    <div><dt>Point of contact</dt><dd><a href="mailto:${e(site.email)}">${e(site.email)}</a> · <a href="${e(site.phoneHref)}">${e(site.phone)}</a></dd></div>
  </dl></div>
  <div>${sectionHead('01', 'Differentiators', 'Why PDI')}<ul class="check-list">${diffs.map((d) => `<li>${check}<span>${e(d)}</span></li>`).join('')}</ul>
    <p>PDI pursues subcontracting and teaming with prime contractors. If you need a small business partner for network, infrastructure, security or compliance-readiness scope, let’s talk.</p></div>
</div></section>
<section class="section section-alt"><div class="container">${sectionHead('02', 'Core competencies', 'What we deliver')}
  <div class="card-grid card-grid-3">${comps.map(([t, d]) => `<div class="card"><h3>${e(t)}</h3><p>${e(d)}</p></div>`).join('')}</div>
</div></section>
<section class="section"><div class="container">${sectionHead('03', 'NAICS', 'Codes and size standards', `Size standards per 13 CFR 121.201 (eCFR current as of ${site.naicsAsOf}). PDI is small under each.`)}
  <div class="table-wrap card"><table class="rate-table"><caption class="sr-only">NAICS codes</caption><thead><tr><th scope="col">NAICS</th><th scope="col">Title</th><th scope="col" class="num">Size standard</th></tr></thead><tbody>${site.naics.map((n) => `<tr><th scope="row" class="mono">${e(n.code)}${n.primary ? ' <span class="badge badge-sm">primary</span>' : ''}</th><td>${e(n.title)}</td><td class="num">${e(n.size)}</td></tr>`).join('')}</tbody></table></div>
</div></section>
${ctaBand('Teaming or a requirement to discuss?', 'Send the scope, the place of performance and the timeline. You’ll get a straight answer on fit within 1 business day.')}`;
  return { path: '/government', title: 'Government Contracting', description: 'Pearson Digital Infrastructure LLC: small business in Huntsville, AL. Primary NAICS 541512. Network, infrastructure, security and CMMC readiness.', body };
}

// ---------------------------------------------------------------- about
export function about() {
  const body = `${pageHero({ crumbs: [{ label: 'About' }], index: '', label: 'About PDI', title: 'Architect-led security <span class="grad-text">for growing organizations.</span>', lead: 'Technology should help people move faster, stay secure, and look credible in front of customers, lenders, auditors and partners.' })}
<section class="section section-tight"><div class="container split split-top">
  <div>${sectionHead('01', 'Why PDI exists', 'Enterprise discipline without the enterprise overhead')}
    <p>Too many businesses run on reactive IT support, weak remote access and backup plans that have never been tested. Pearson Cyber Defense exists to close that gap with practical, security-first architecture: secure perimeters, hardened access paths, monitored critical services, tested recovery plans, and a clear view of the systems your business depends on.</p>
    <p>PDI is led by its founder, a career network infrastructure and datacenter architect. When you hire PDI, the architect who designs your solution is the engineer who builds and supports it. Nothing gets lost in a hand-off, because there isn’t one.</p>
  </div>
  <div class="card id-card"><p class="mono">official business identity</p><dl>
    <div><dt>Legal entity</dt><dd>${e(site.legalName)}</dd></div><div><dt>Public brand</dt><dd>${e(site.brand)}</dd></div>
    <div><dt>${e(site.address.label)}</dt><dd>${e(site.address.street)}, ${e(site.address.city)}, ${e(site.address.region)} ${e(site.address.postal)}</dd></div>
    <div><dt>Phone</dt><dd><a href="${e(site.phoneHref)}">${e(site.phone)}</a></dd></div><div><dt>Email</dt><dd><a href="mailto:${e(site.email)}">${e(site.email)}</a></dd></div>
    <div><dt>Web</dt><dd>mrpearson.net</dd></div>
  </dl></div>
</div></section>
<section class="section section-alt"><div class="container">${sectionHead('02', 'Operating principles', 'How we defend')}
  <ol class="steps">${principles.map((p, i) => `<li class="step"><span class="step-n mono">0${i + 1}</span><h3>${e(p.title)}</h3><p>${e(p.text)}</p></li>`).join('')}</ol>
</div></section>
<section class="section"><div class="container">${sectionHead('03', 'The PDI lab', 'We run what we sell.', 'PDI’s own infrastructure is the reference build for everything we deliver.')}
  <div class="lab-grid">${lab.map((x) => `<div class="card lab-card"><span class="code">${e(x.code)}</span><h3>${e(x.title)}</h3><p>${e(x.text)}</p></div>`).join('')}</div>
</div></section>
<section class="section section-alt"><div class="container split split-top">
  <div>${sectionHead('04', 'Service area', 'Local enough to know the mission')}<p>Primary: ${e(site.serviceArea.primary.join(', '))}. Regional: ${e(site.serviceArea.regional.join(', '))}. ${e(site.serviceArea.remote)}</p></div>
  <div>${sectionHead('05', 'Delivery model', 'How engagements run')}<ul class="check-list">${delivery.map((d) => `<li>${check}<span><strong>${e(d.step)}.</strong> ${e(d.text)}</span></li>`).join('')}</ul></div>
</div></section>
${ctaBand()}`;
  return { path: '/about', title: 'About', description: 'Pearson Digital Infrastructure LLC d/b/a Pearson Cyber Defense: architect-led cybersecurity and infrastructure from Huntsville, Alabama.', body };
}

// ---------------------------------------------------------------- contact
export function contact() {
  const body = `${pageHero({ crumbs: [{ label: 'Contact' }], index: '', label: 'Start the conversation', title: 'Get a <span class="grad-text">free assessment.</span>', lead: 'Tell us what you’re running and what you’re worried about. We reply within 1 business day.' })}
<section class="section section-tight"><div class="container split split-top">
  ${contactForm('contact')}
  <div class="contact-side">
    <div class="card"><p class="mono">direct</p><ul class="contact-list"><li><span class="mono">phone</span><a href="${e(site.phoneHref)}">${e(site.phone)}</a></li><li><span class="mono">email</span><a href="mailto:${e(site.email)}">${e(site.email)}</a></li><li><span class="mono">hours</span><span>${e(site.businessHours)}</span></li></ul></div>
    <div class="card card-warn"><p class="mono">existing client with a P1?</p><p>Call <a href="${e(site.phoneHref)}">${e(site.phone)}</a>. Email isn’t monitored after hours. After-hours P1 response is best effort, with a 2-hour target.</p></div>
    <div class="card"><p class="mono">${e(site.address.label.toLowerCase())}</p><address>${e(site.legalName)}<br>${e(site.dba)}<br>${e(site.address.street)}<br>${e(site.address.city)}, ${e(site.address.region)} ${e(site.address.postal)}</address></div>
  </div>
</div></section>`;
  return { path: '/contact', title: 'Contact & Free Assessment', description: 'Request a free assessment from Pearson Cyber Defense in Huntsville, AL. Call (256) 675-9961 or email admin@mrpearson.net. Replies within 1 business day.', body, jsonLd: orgJsonLd };
}

// ---------------------------------------------------------------- payments
export function payments() {
  const body = `${pageHero({ crumbs: [{ label: 'Payments' }], index: '', label: 'Secure billing', title: 'Pay an <span class="grad-text">invoice.</span>', lead: 'Pay a PDI invoice securely through Stripe Checkout. PDI never sees or stores your card number.' })}
<section class="section section-tight"><div class="container split split-top">
  <form class="form card" data-invoice-form novalidate>
    <input type="hidden" name="planKey" value="custom-invoice">
    <div class="form-grid">
      <div class="field"><label for="pay-invoice">Invoice number</label><input id="pay-invoice" name="invoiceNumber" type="text" maxlength="40" autocomplete="off" placeholder="As shown on your invoice"></div>
      <div class="field"><label for="pay-amount">Amount (USD) <span aria-hidden="true">*</span></label><input id="pay-amount" name="amount" type="number" min="25" step="0.01" inputmode="decimal" required></div>
      <div class="field field-full"><label for="pay-email">Email for the receipt <span aria-hidden="true">*</span></label><input id="pay-email" name="email" type="email" autocomplete="email" required maxlength="160"></div>
    </div>
    <div class="form-foot"><button class="btn btn-primary" type="submit">Continue to secure checkout ${arrow}</button><p class="muted small">You’ll be redirected to Stripe to complete payment. Minimum $25.</p></div>
    <p class="form-status" role="status" aria-live="polite"></p>
  </form>
  <div class="contact-side">
    <div class="card"><p class="mono">how billing works</p><ul class="check-list"><li>${check}<span>Work is invoiced per your signed proposal or agreement.</span></li><li>${check}<span>Prepaid blocks, projects and monthly services are invoiced, never sold as one-click plans.</span></li><li>${check}<span>Questions about an invoice? Email <a href="mailto:${e(site.email)}">${e(site.email)}</a>.</span></li></ul></div>
  </div>
</div></section>`;
  return { path: '/payments', title: 'Pay an Invoice', description: 'Pay a Pearson Cyber Defense invoice securely through Stripe Checkout. PDI never sees or stores your card number.', body };
}

// ---------------------------------------------------------------- legal pages (content: src/content/legal.mjs)
// A page is a draft until approved[key] is true. Drafts build to /_drafts/, carry noindex and a banner,
// and are never linked. The tests refuse to publish a page that still contains a ⟦…⟧ marker.
const draftBanner = '<div class="callout callout-warn"><strong>DRAFT, pending attorney review.</strong> Not published or linked until the Owner and counsel approve it. Highlighted ⟦CONFIRM⟧ items must be verified or decided first.</div>';

// Escape, then allow **bold**, `code`, [text](url) and highlight ⟦…⟧ markers.
function inline(s) {
  return e(s)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, text, url) => /^https?:/.test(url) ? `<a href="${url}" rel="noopener" target="_blank">${text}</a>` : `<a href="${url}">${text}</a>`)
    .replace(/⟦([^⟧]*)⟧/g, '<mark class="todo">⟦$1⟧</mark>');
}
function legalBlock(b) {
  if (typeof b === 'string') return `<p>${inline(b)}</p>`;
  if (b.list) return `<ul>${b.list.map((x) => `<li>${inline(x)}</li>`).join('')}</ul>`;
  if (b.table) return `<div class="table-wrap card"><table class="rate-table"><thead><tr>${b.table.head.map((h) => `<th scope="col">${inline(h)}</th>`).join('')}</tr></thead><tbody>${b.table.rows.map((r) => `<tr><th scope="row">${inline(r[0])}</th>${r.slice(1).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  return '';
}
const slugify = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

export function legalPage(key) {
  const doc = legalDocs[key];
  const isDraft = !legalApproved[key];
  const toc = `<nav class="legal-toc card" aria-label="On this page"><p class="mono">on this page</p><ol>${doc.sections.map((s) => `<li><a href="#${slugify(s.h)}">${e(s.h)}</a></li>`).join('')}</ol></nav>`;
  const body = `${pageHero({ crumbs: [{ label: doc.title }], index: '', label: isDraft ? 'Draft' : 'Legal', title: e(doc.title), lead: `Effective date: ${legalEffective}` })}
<section class="section section-tight"><div class="container narrow prose">${isDraft ? draftBanner : ''}
${doc.intro.map((p) => `<p>${inline(p)}</p>`).join('')}
${toc}
${doc.sections.map((s) => `<h2 id="${slugify(s.h)}">${e(s.h)}</h2>${s.blocks.map(legalBlock).join('')}`).join('\n')}
</div></section>`;
  return { path: doc.path, title: isDraft ? `${doc.title} (Draft)` : doc.title, description: doc.description, body, noindex: isDraft, draft: isDraft, legal: key };
}

// ---------------------------------------------------------------- 404
// ---------------------------------------------------------------- engineering (pipeline showcase)
const fmtDate = (iso) => new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC' });
const fmtDur = (s) => (s >= 60 ? `${Math.floor(s / 60)}m ${Math.round(s % 60)}s` : `${Math.round(s)}s`);
const runnerLabel = (r) => (r.runner === 'jenkins' ? 'Jenkins (internal)' : 'Engineering workstation');
const stageMark = (res) => ({ passed: `<span class="pipe-res pipe-pass">${check} passed</span>`, failed: `<span class="pipe-res pipe-fail">${cross} failed</span>`, skipped: '<span class="pipe-res pipe-skip">skipped</span>', 'not-run': '<span class="pipe-res pipe-skip">not run</span>' }[res] || '');

export function engineering() {
  const runs = loadRuns();
  const last = runs[0] || null;
  const byId = last ? Object.fromEntries(last.stages.map((s) => [s.id, s])) : {};
  const latest = last ? `<div class="card pipe-latest">
    <p class="mono">latest run · ${e(last.id)}</p>
    <ul class="fact-grid">
      <li><strong>${last.result === 'passed' ? 'Passed' : 'Failed'}</strong><span>result</span></li>
      <li><strong>${last.totals.checks - last.totals.failed} / ${last.totals.checks}</strong><span>automated checks passed</span></li>
      <li><strong>${e(fmtDur(last.durationSec))}</strong><span>total stage time</span></li>
      <li><strong>${last.release ? `v${e(last.release.version)}` : 'n/a'}</strong><span>release under test</span></li>
    </ul>
    <p class="small muted">${e(fmtDate(last.finishedAt))} · ran on: ${e(runnerLabel(last))}${last.sbom ? ` · SBOM: ${last.sbom.components} components (CycloneDX)` : ''}${last.audit ? ` · dependency gate: ${e(last.audit.gate)}` : ''}</p>
  </div>` : '<div class="card"><p>No pipeline runs have been published yet.</p></div>';
  const stageList = `<ol class="pipe">${pipelineStages.map((s, i) => {
    const r = byId[s.id];
    return `<li class="pipe-stage">
    <span class="step-n">${String(i + 1).padStart(2, '0')}</span>
    <div class="pipe-body"><h3>${e(s.name)}</h3><p>${e(s.what)}</p>
      <p class="chip-row">${s.controls.map((c) => `<span class="chip">NIST ${e(c)}</span>`).join('')}</p></div>
    <div class="pipe-meta">${r ? `${stageMark(r.result)}${r.checks ? `<span class="mono small">${r.checks.passed} checks</span>` : ''}<span class="mono small">${e(fmtDur(r.durationSec))}</span>` : ''}</div>
  </li>`;
  }).join('')}</ol>`;
  const history = runs.length ? `<div class="table-wrap card"><table class="rate-table"><caption class="sr-only">Recent pipeline runs</caption>
    <thead><tr><th scope="col">Date</th><th scope="col">Ran on</th><th scope="col">Release</th><th scope="col">Result</th><th scope="col" class="num">Checks</th><th scope="col" class="num">Time</th></tr></thead>
    <tbody>${runs.slice(0, 10).map((r) => `<tr><th scope="row">${e(fmtDate(r.finishedAt))}</th><td>${e(runnerLabel(r))}</td><td class="mono">${r.release ? `v${e(r.release.version)}` : 'n/a'}</td><td>${r.result === 'passed' ? 'passed' : 'failed'}</td><td class="num">${r.totals.checks - r.totals.failed} / ${r.totals.checks}</td><td class="num">${e(fmtDur(r.durationSec))}</td></tr>`).join('')}</tbody></table></div>` : '';
  const controlRows = Object.keys(nistControls).map((id) => `<tr><th scope="row" class="mono">${e(id)}</th><td>${e(nistControls[id])}</td><td>${e(controlEvidence[id])}</td></tr>`).join('');
  const body = `${pageHero({ crumbs: [{ label: 'Engineering' }], index: '', label: 'Engineering', title: 'How we <span class="grad-text">ship.</span>', lead: 'Every release of this website goes through the same kind of pipeline we build for clients: facts checked, code built from recorded source, the live application tested, secrets and dependencies scanned, and the deployment rehearsed before production. These are the real results.' })}
<section class="section section-tight"><div class="container">${latest}</div></section>
<section class="section section-alt"><div class="container">${sectionHead('01', 'The pipeline', 'Seven stages, every release', 'A release can reach production only when every stage passes. Results shown are from the latest published run.')}
  ${stageList}
</div></section>
<section class="section"><div class="container">${sectionHead('02', 'Run history', 'Recent runs', 'Published automatically from each run’s record: only results, counts and timings, never logs or internal details.')}
  ${history}
</div></section>
<section class="section section-alt"><div class="container">${sectionHead('03', 'Controls', 'Mapped to NIST SP 800-171', 'How this pipeline supports configuration-management and flaw-remediation requirements that defense contractors are assessed against. Requirement text quoted from NIST SP 800-171 Rev. 2.')}
  <div class="table-wrap card"><table class="rate-table"><caption class="sr-only">NIST SP 800-171 requirements and how the pipeline supports them</caption><thead><tr><th scope="col">Req.</th><th scope="col">Requirement</th><th scope="col">How this pipeline supports it</th></tr></thead><tbody>${controlRows}</tbody></table></div>
  <p class="small muted">Supporting a requirement is not the same as meeting it for your organization; that is decided in your own assessment.</p>
</div></section>
<section class="section"><div class="container split split-top">
  <div>${sectionHead('04', 'Architecture', 'Internal tools stay internal')}
    <ul class="check-list">
      <li>${check}<span>Source lives in a private Git server; the build server runs these stages on the internal network.</span></li>
      <li>${check}<span>Only a sanitized run record leaves the network, inside a release. Nothing on the internet connects in.</span></li>
      <li>${check}<span>Production changes are approved by a person and applied by scripts that check everything first and roll back on their own.</span></li>
    </ul></div>
  <div class="card"><h3>Want this for your team?</h3><p>We design and run pipelines like this with Jenkins, Gitea or GitHub, Ansible and Terraform, sized to your team and your compliance needs.</p>
    <div class="btn-row"><a class="btn btn-primary" href="/services/devops-ci-cd">DevOps &amp; CI/CD ${arrow}</a><a class="btn btn-ghost" href="/contact">Talk to us</a></div></div>
</div></section>`;
  return { path: '/engineering', title: 'Engineering: How We Ship', description: 'The real release pipeline behind mrpearson.net: tested facts, source builds, live app tests, secret and dependency scans, and rehearsed deployments.', body };
}

export function notFound() {
  const body = `<section class="section notfound"><div class="container narrow">
  <div class="terminal"><div class="terminal-bar"><span></span><span></span><span></span><p class="mono">admin@mrpearson.net: ~</p></div>
  <ol class="terminal-body"><li class="t-cmd" data-404-path>$ curl -I https://mrpearson.net/this-page</li><li class="t-err">HTTP/2 404: route not found</li><li class="t-out">[hint] the page moved, or never existed</li><li class="t-ok">✓ try one of these instead</li></ol></div>
  <h1>Page not found</h1>
  <div class="btn-row"><a class="btn btn-primary" href="/">Home ${arrow}</a><a class="btn btn-ghost" href="/services">Services</a><a class="btn btn-ghost" href="/pricing">Pricing</a><a class="btn btn-ghost" href="/contact">Contact</a></div>
</div></section>`;
  return { path: '/404', title: 'Page Not Found', description: 'The page you requested could not be found on mrpearson.net. Try the home page, services, pricing or contact.', body, noindex: true };
}

export function allPages() {
  return [home(), servicesIndex(), ...services.map(servicePage), pricing(), serviceLevels(), defense(), government(), about(), engineering(), contact(), payments(), legalPage('privacy'), legalPage('terms'), legalPage('security'), notFound()];
}
