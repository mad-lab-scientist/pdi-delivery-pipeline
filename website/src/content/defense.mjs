// CMMC facts for the Defense page.
// Source of truth: knowledge/pdi-executive-playbooks/03-cmmc-2-readiness-playbook.md
// (regulatory details as understood Sept 2026; verify against 32 CFR Part 170 and DFARS 252.204-7021).

export const cmmc = {
  asOf: 'October 2026',
  sources: '32 CFR Part 170 (CMMC Program rule), DFARS 252.204-7012 / -7019 / -7020 / -7021, and DoD CIO CMMC resources',
  phase2: { date: '2026-11-10', iso: '2026-11-10T00:00:00-06:00', label: 'November 10, 2026' },
  phases: [
    { n: 1, start: 'Nov 10, 2025', what: 'Level 1 and Level 2 self-assessments required in applicable solicitations' },
    { n: 2, start: 'Nov 10, 2026', what: 'Level 2 certification by a C3PAO required in applicable solicitations' },
    { n: 3, start: 'Nov 10, 2027', what: 'Level 3 (DCMA DIBCAC) requirements begin' },
    { n: 4, start: 'Nov 10, 2028', what: 'Full implementation across applicable contracts' },
  ],
  levels: [
    { level: 'Level 1', protects: 'FCI', requirements: '15 basic safeguarding requirements (FAR 52.204-21)', assessment: 'Annual self-assessment and affirmation in SPRS' },
    { level: 'Level 2', protects: 'CUI', requirements: '110 requirements of NIST SP 800-171 Rev 2', assessment: 'Self-assessment or C3PAO certification (per contract) every 3 years, plus annual affirmation' },
    { level: 'Level 3', protects: 'CUI on critical programs', requirements: 'Level 2 plus selected NIST SP 800-172 requirements', assessment: 'DCMA DIBCAC government assessment, after a final Level 2 C3PAO certification' },
  ],
  facts: [
    { k: '110', v: 'NIST SP 800-171 Rev 2 requirements behind CMMC Level 2' },
    { k: '−203 to 110', v: 'Range of the SPRS score (DoD Assessment Methodology)' },
    { k: '72 hours', v: 'To report a cyber incident to DoD under DFARS 252.204-7012' },
    { k: '3 years', v: 'Level 2 assessment cycle (self-assessment or C3PAO), with annual affirmations' },
  ],
  method: [
    { stage: 'Qualify', time: '1 call', out: 'FCI only, or CUI? Which contracts and flow-downs? When is the next award?' },
    { stage: 'Scope & gap', time: 'Weeks 1–4', out: 'CUI data-flow diagram, asset inventory by category, 110-requirement gap assessment, preliminary SPRS score' },
    { stage: 'Remediate', time: 'Weeks 4–16', out: 'Highest-weight gaps first (MFA, encryption, logging, access control, incident response), SSP, POA&M' },
    { stage: 'Evidence', time: 'Weeks 12–24', out: 'Monthly evidence program running, policies adopted, training records, mock assessment' },
    { stage: 'Assessment', time: 'As scheduled', out: 'C3PAO readiness review, evidence binder, support during the assessment' },
    { stage: 'Sustain', time: 'Ongoing', out: 'Evidence program, annual affirmation support, change tracking' },
  ],
  boundaries: [
    'PDI does not certify anyone. Level 2 certification comes from an authorized C3PAO; Level 3 assessments are performed by DCMA DIBCAC.',
    'PDI is not a C3PAO or a FedRAMP-authorized cloud provider.',
    'Your senior official signs SPRS affirmations. PDI prepares the evidence with you.',
    'Readiness work does not guarantee an assessment outcome.',
    'When PDI manages your security tools, PDI becomes an External Service Provider, and our people and tools are in your assessment scope. We document that shared responsibility up front.',
  ],
};
