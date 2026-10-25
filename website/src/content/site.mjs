// Company facts for mrpearson.net.
// Source of truth: knowledge/pdi-company-core/01-company-profile.md and
// knowledge/pdi-executive-playbooks/08-government-contracting-playbook.md.
// Change a fact there first, then here. The test suite cross-checks the key values.

export const site = {
  brand: 'Pearson Cyber Defense',
  legalName: 'Pearson Digital Infrastructure LLC',
  dba: 'd/b/a Pearson Cyber Defense',
  url: 'https://mrpearson.net',
  tagline: 'Cyber defense and digital infrastructure built for serious business.',
  positioning: 'Architect-led security for growing organizations.',
  phone: '(256) 675-9961',
  phoneHref: 'tel:+12566759961',
  email: 'admin@mrpearson.net',
  address: {
    label: 'Business office',
    street: '7027 Old Madison Pike NW, Suite 108',
    city: 'Huntsville',
    region: 'AL',
    postal: '35806',
    country: 'US',
  },
  businessHours: 'Monday–Friday, 8:00 AM–6:00 PM Central',
  serviceArea: {
    primary: ['Huntsville', 'Madison', 'Redstone Arsenal', 'Cummings Research Park'],
    regional: ['North Alabama', 'the Tennessee Valley', 'Decatur', 'Athens'],
    remote: 'Remote clients anywhere in the U.S.',
  },
  // 13 CFR 121.201, eCFR current as of 2026-09-25 (Government Contracting Playbook, Step 2)
  naicsAsOf: '2026-09-25',
  naics: [
    { code: '541512', title: 'Computer Systems Design Services', size: '$34.0M', primary: true },
    { code: '541513', title: 'Computer Facilities Management Services', size: '$37.0M' },
    { code: '541519', title: 'Other Computer Related Services', size: '$34.0M' },
    { code: '518210', title: 'Computing Infrastructure Providers, Data Processing, Web Hosting, and Related Services', size: '$40.0M' },
    { code: '541511', title: 'Custom Computer Programming Services', size: '$34.0M' },
    { code: '541690', title: 'Other Scientific and Technical Consulting Services', size: '$19.0M' },
  ],
  readinessBadges: ['NIST SP 800-171 aligned', 'CMMC-ready', 'SOC 2-style practices', 'HIPAA-aware'],
};

// The four operating principles (Company Profile, "the four pillars").
export const principles = [
  { title: 'Proactive over reactive', text: 'Monitoring, patching and backup verification are core services, not add-ons.' },
  { title: 'Security first', text: 'Identity, access control, MFA and recovery planning are built in from day one.' },
  { title: 'Business clarity', text: 'Plain-English reports, tickets and documentation give owners real visibility.' },
  { title: 'Scalable delivery', text: 'The same discipline serves a home office, a growing firm or a multi-site organization.' },
];

// Delivery model (Company Profile). "Operate" follows SLA v2.0: business-hours operations, no 24/7 staffing.
export const delivery = [
  { step: 'Assess', text: 'Free initial assessment with no commitment. We inventory assets, access paths, backups and risks.' },
  { step: 'Stabilize', text: 'Fix the critical exposures first: MFA, backups that actually restore, firewall hygiene, patching.' },
  { step: 'Modernize', text: 'Standardize, move workloads where they belong, automate the repetitive work and document everything.' },
  { step: 'Operate', text: 'Business-hours operations against published response targets, with monthly reports and quarterly reviews.' },
];

// PDI's own infrastructure ("we run what we sell"). Product names only: no IPs, versions or topology.
export const lab = [
  { code: 'R730', title: 'Private cloud', text: 'Proxmox VE on a Dell PowerEdge R730, including GPU passthrough for private AI.' },
  { code: 'FGT', title: 'Segmented perimeter', text: 'Fortinet FortiGate 60F and FortiAP with VLAN segmentation and FortiAnalyzer logging.' },
  { code: 'SIEM', title: 'Security visibility', text: 'Wazuh SIEM/XDR, Zabbix monitoring and OpenVAS vulnerability scanning.' },
  { code: 'AI', title: 'Private AI', text: 'Ollama and Open WebUI on an NVIDIA Tesla P40: 13 specialized agents, and the data never leaves PDI hardware.' },
  { code: 'CI', title: 'Automation and CI', text: 'n8n workflows, Jenkins pipelines and a self-hosted Gitea, all on PDI-owned hardware.' },
  { code: 'DR', title: 'Verified backups', text: 'Nightly encrypted, checksum-verified backups with restore dry runs, because a backup isn’t real until it restores.' },
];

export const techStack = [
  'Fortinet FortiGate', 'FortiAnalyzer', 'Wazuh', 'Proxmox VE', 'Dell PowerEdge', 'Microsoft 365', 'Entra ID', 'Azure', 'AWS',
  'Veeam', 'Linux', 'Windows Server', 'Docker', 'Kubernetes', 'Terraform', 'Ansible', 'Jenkins', 'Git', 'Prometheus', 'Grafana',
  'Nginx', 'Node.js', 'n8n', 'Ollama',
];
