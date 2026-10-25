// Service levels shown on mrpearson.net.
// Source of truth: knowledge/pdi-company-core/04-sla-and-priority-matrix.md (SLA v2.0, solo operator, adopted 2026-09-30).
// test/run-tests.mjs parses that file and fails the build if the response targets drift.

export const sla = {
  version: '2.0',
  adopted: '2026-09-30',
  coverage: [
    { item: 'Business hours', value: 'Monday–Friday, 8:00 AM–6:00 PM Central, excluding U.S. federal holidays' },
    { item: 'P2–P4 requests', value: 'Client portal or email (admin@mrpearson.net)' },
    { item: 'P1 emergencies', value: 'Phone call required: (256) 675-9961. Email is not monitored after hours.' },
    { item: 'After hours', value: 'P1 only, best effort, with a target response within 2 hours, billed at after-hours rates' },
    { item: 'Monitoring alerts', value: 'Reviewed during business hours. Critical alerts reach PDI’s phone at any hour, but after-hours response is best effort, not staffed.' },
  ],
  priorities: [
    { p: 'P1', name: 'Critical', definition: 'Business stopped, an active security incident, a site, server or email down for everyone, or data at risk', response: '1 business hour', updates: 'Every 2 hours while active', restore: 'Continuous effort during business hours until restored or worked around' },
    { p: 'P2', name: 'High', definition: 'Major degradation: a key person or team can’t work, or backups are failing', response: '4 business hours', updates: 'End of each business day', restore: '2 business days' },
    { p: 'P3', name: 'Normal', definition: 'One user affected and a workaround exists', response: 'Next business day', updates: 'Every 2 business days', restore: '5 business days' },
    { p: 'P4', name: 'Request', definition: 'How-to questions, new users, change requests and scheduled work', response: '2 business days', updates: 'On completion', restore: 'As scheduled with you' },
  ],
  responseMeaning: '“Response” means PDI has personally acknowledged the issue and started work. Auto-replies don’t count. The clock starts when the request arrives through the proper channel and pauses while PDI waits on you or a third-party vendor.',
  maintenance: 'Tuesday and Thursday, 6:00–10:00 PM Central, with at least 2 business days’ notice. Critical security patches may be applied sooner, with same-day notice.',
  security: [
    'Any suspected compromise is treated as P1: contain, preserve evidence, recover.',
    'Regulatory reporting stays with the client (for defense contractors, that includes the DFARS 252.204-7012 72-hour report to DoD). PDI supports you with the facts and evidence.',
  ],
  continuity: [
    'Planned absences of more than 2 business days are announced at least 5 business days in advance.',
    'You always keep your own break-glass admin access. PDI never holds the only key.',
    'Every client has current runbooks and network documentation, so another qualified engineer could take over.',
  ],
  exclusions: 'Outages caused by third parties (ISP, Microsoft 365, cloud providers, software vendors), client-caused changes, unsupported or end-of-life hardware and software, force majeure, and work outside the agreed scope (quoted separately at Labor Rate Card rates).',
  measurement: 'PDI measures response attainment per priority and reports it monthly. The internal goal is at least 95% of tickets meeting the response target. No financial service credits are offered during the first 12 months; credits will be revisited once 6+ months of measured data exist.',
  no247: 'PDI does not provide 24/7 staffed monitoring (NOC or SOC). If your environment needs round-the-clock coverage, we’ll say so up front and help you scope it with a 24/7 provider, or it stays out of scope.',
};
