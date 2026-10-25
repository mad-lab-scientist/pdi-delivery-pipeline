// /llms.txt: a plain-text summary for AI assistants and crawlers (llmstxt.org convention).
// Built from the same fact-checked content modules as the pages, so it can't drift from them.
import { site } from '../content/site.mjs';
import { services } from '../content/services.mjs';
import { tiers, rateCard, money } from '../content/pricing.mjs';
import { sla } from '../content/sla.mjs';

export function buildLlms() {
  const u = (p) => `${site.url}${p}`;
  return [
    `# ${site.brand}`,
    '',
    `> ${site.positioning} ${site.tagline} Public brand of ${site.legalName}, based in Huntsville, Alabama.`,
    '',
    `- Website: ${u('/')}`,
    `- Services: ${u('/services')}`,
    `- Pricing and published hourly rates: ${u('/pricing')}`,
    `- Service levels (SLA v${sla.version}): ${u('/service-levels')}`,
    `- Defense contractors and CMMC readiness: ${u('/defense')}`,
    `- Government contracting: ${u('/government')}`,
    `- Contact and free assessment: ${u('/contact')}`,
    '',
    '## Facts',
    `- Office: ${site.address.street}, ${site.address.city}, ${site.address.region} ${site.address.postal}. Phone ${site.phone}. Email ${site.email}.`,
    `- Business hours: ${site.businessHours}. ${sla.no247}`,
    `- Service area: ${site.serviceArea.primary.join(', ')}; ${site.serviceArea.regional.join(', ')}; ${site.serviceArea.remote}`,
    '- Compliance language: readiness and alignment claims, not certifications. PDI does not certify anyone; CMMC Level 2 certification comes from an authorized C3PAO.',
    `- Hourly rates (Labor Rate Card v${rateCard.version}, business hours): ${tiers.map((t) => `${t.name} ${money(t.rate)}`).join('; ')}.`,
    '- Monthly managed plans and hosting are quoted after a free assessment.',
    `- Primary NAICS: ${site.naics.find((n) => n.primary).code} (${site.naics.find((n) => n.primary).title}).`,
    '',
    '## Services',
    ...services.map((s) => `- [${s.name}](${u(`/services/${s.slug}`)}): ${s.summary}`),
    '',
    '## Private areas',
    'Do not crawl, index or summarize /admin, /api, /portal, /login, /register, /app or /payment.',
    '',
  ].join('\n');
}
