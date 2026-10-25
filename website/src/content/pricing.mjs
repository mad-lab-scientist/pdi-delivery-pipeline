// Public pricing for mrpearson.net.
// Source of truth: knowledge/pdi-company-core/08-labor-rate-card.md (Labor Rate Card v1.0, adopted 2026-09-30).
// test/run-tests.mjs parses that file and fails the build if anything here drifts from it.
// Deliberately NOT published: loaded costs, margins, government (federal) rates, and the legacy monthly plan prices.

export const rateCard = {
  version: '1.0',
  adopted: '2026-09-30',
  basis: 'Standard business hours, Monday–Friday 8:00 AM–6:00 PM Central, remote unless noted. USD per hour.',
};

export const tiers = [
  { id: 't1', name: 'T1 Support Technician', rate: 125, work: 'Help desk, password and MFA resets, user and device issues, printers, basic Microsoft 365' },
  { id: 't2', name: 'T2 Systems & Network Administrator', rate: 175, work: 'Servers, Microsoft 365 and Entra administration, endpoint management, FortiGate and VPN changes, backup restores, VM administration, web operations' },
  { id: 't3', name: 'T3 Senior Engineer / Architect', rate: 225, work: 'Network and VLAN design, Proxmox and virtualization architecture, cloud migrations, DR design and testing, DevOps and CI/CD, complex troubleshooting' },
  { id: 'sec', name: 'Security Engineering', rate: 225, work: 'Hardening, vulnerability remediation, SIEM and Wazuh tuning, firewall policy review, EDR deployment' },
  { id: 'ir', name: 'Incident Response', rate: 275, work: 'Active compromise, ransomware, business email compromise containment and investigation' },
  { id: 'grc', name: 'Compliance & vCISO', rate: 275, work: 'CMMC and NIST SP 800-171 readiness, SSP and POA&M, policies, SOC 2 and HIPAA readiness, vCISO advisory' },
  { id: 'ai', name: 'Automation & AI Engineering', rate: 225, work: 'n8n workflows, private AI (Ollama and Open WebUI) builds, scripting, integrations' },
  { id: 'res-remote', name: 'Residential: remote', rate: 100, work: 'Home and family support over a remote session' },
  { id: 'res-onsite', name: 'Residential: on-site', rate: 125, work: 'In-home visit' },
];

export const tierById = Object.fromEntries(tiers.map((t) => [t.id, t]));

// Which rate applies to each service line (Rate Card, "Which rate applies to each PDI service line").
// Each entry: [tierId, label]. VPS Hosting is not hourly.
export const serviceRates = {
  'help-desk': [['t1', 'Support'], ['t2', 'Escalation'], ['t3', 'Senior escalation']],
  'infrastructure': [['t2', 'Administration'], ['t3', 'Design and architecture']],
  'network-management': [['t2', 'Routine changes'], ['t3', 'Design and segmentation']],
  'cloud-solutions': [['t3', 'Cloud and migrations'], ['t2', 'Microsoft 365 administration']],
  'devops-ci-cd': [['t3', 'Pipelines, IaC and platforms']],
  'private-cloud-virtualization': [['t2', 'Administration'], ['t3', 'Architecture']],
  'secure-hosting': [['t2', 'Web operations']],
  'backup-recovery': [['t2', 'Restores'], ['t3', 'DR planning and testing']],
  'cybersecurity': [['sec', 'Security engineering'], ['ir', 'Incident response']],
  'soc-monitoring-log-management': [['sec', 'Analyst and tuning work']],
  'compliance-readiness-evidence': [['grc', 'Compliance and vCISO']],
  'ai-automation-operations': [['ai', 'Automation and AI engineering']],
  'vps-hosting': [['t2', 'Administration beyond plan scope']],
};

export const premiums = [
  { rule: 'Extended hours (weekdays 6–10 PM)', policy: '1.25× the tier rate' },
  { rule: 'Overnight and weekends', policy: '1.5× the tier rate' },
  { rule: 'Holidays and emergency on-site dispatch', policy: '2× the tier rate, 2-hour minimum on-site' },
  { rule: 'Remote work', policy: 'Billed in 15-minute increments, 30-minute minimum' },
  { rule: 'Scheduled on-site work', policy: '1-hour minimum' },
  { rule: 'Travel', policy: 'No trip charge in the primary area (Huntsville, Madison, Redstone Arsenal, Cummings Research Park). Regional travel beyond 30 minutes each way is billed at the T1 rate.' },
];

// Prepaid block hours: dollar-value blocks drawn down at the tier rates, 12-month expiry.
export const blocks = {
  expiryMonths: 12,
  sizes: [
    { hours: 20, discount: 0.10 },
    { hours: 40, discount: 0.15 },
  ],
  exampleTier: 't2',
};

export function blockExample(hours, discount, tierId = blocks.exampleTier) {
  const rate = tierById[tierId].rate;
  const list = hours * rate;
  const price = Math.round(list * (1 - discount) * 100) / 100;
  return { tier: tierById[tierId], hours, discount, list, price, saved: Math.round((list - price) * 100) / 100 };
}

export const projects = {
  method: 'Estimated hours × tier rate, plus 15–20% contingency. New scope is handled with a written change order.',
};

// Market references (Rate Card, "Step 5: market check"). Published so clients can check the numbers themselves.
export const marketRefs = [
  { source: 'Clutch, IT Services Pricing Guide (updated 2026-09-21)', figure: 'Most common MSP rate: $100–149/h', url: 'https://clutch.co/it-services/msp/pricing' },
  { source: 'Flamingo, MSP Pricing Models (Aug 2026)', figure: 'Break-fix: $125–250/h standard, $250–500/h after-hours or emergency', url: 'https://www.flamingo.run/blog/msp-pricing-models' },
  { source: 'Managed Services Near You, Pricing Guide 2025', figure: 'Project engineers: $125–250/h; block hours 10–20% below standard', url: 'https://managedservicesnearyou.com/pricing-guide' },
  { source: 'SideChannel, vCISO Pricing (2026-04-22)', figure: 'vCISO: $200–400/h', url: 'https://sidechannel.com/blog/the-ultimate-guide-to-vciso-pricing-everything-you-need-to-know/' },
  { source: 'Corsica Technologies, CMMC Compliance Consulting (2026-08-07)', figure: 'CMMC consultants: $200–400/h', url: 'https://corsicatech.com/blog/cmmc-compliance-consulting/' },
  { source: 'Talo, Tech Support Prices (2026-04-01)', figure: 'Home users: $50–150/h', url: 'https://talo.com/costs/tech-support-prices' },
];

export const money = (n) => '$' + n.toLocaleString('en-US', { minimumFractionDigits: Number.isInteger(n) ? 0 : 2, maximumFractionDigits: 2 });
