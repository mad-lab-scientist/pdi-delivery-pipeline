// Website legal pages: Privacy Policy, Terms of Use, Security & Responsible Disclosure.
// DRAFTS written from how mrpearson.net actually works (audited 2026-10-22). They are not legal advice;
// have an Alabama-licensed attorney review before publishing.
//
// Markers:  ⟦CONFIRM: …⟧ = a fact or decision the Owner/counsel must confirm.
// Publishing: set approved.<page> = true. The test suite refuses to publish a page that still contains ⟦…⟧.
// Inline markup: **bold**, `code`, [text](url).

export const approved = { privacy: false, terms: false, security: false };
export const effectiveDate = '⟦CONFIRM: effective date⟧';

const CO = 'Pearson Digital Infrastructure LLC, doing business as Pearson Cyber Defense ("PDI," "we," "us," or "our")';

export const privacy = {
  path: '/privacy',
  title: 'Privacy Policy',
  description: 'How Pearson Digital Infrastructure LLC collects, uses, shares and protects personal information on mrpearson.net and the PDI client portal.',
  intro: [
    `This Privacy Policy explains how ${CO} collects, uses, shares and protects personal information when you visit mrpearson.net, use our client portal, contact us, or pay an invoice online (together, the "Site").`,
    'It does not cover information we process on behalf of our clients while delivering managed services. That information is governed by the client’s written service agreement with us.',
  ],
  sections: [
    { h: 'Information we collect', blocks: [
      'We collect only what we need to respond to you, deliver our services, get paid, and keep our systems secure.',
      { list: [
        '**Contact and assessment requests:** your name, email address, company or household name, the service you’re interested in, your message, and the page you contacted us from.',
        '**Client portal accounts:** username, email address, company, phone number (optional), and password. ⟦CONFIRM: passwords are stored only as salted one-way hashes⟧',
        '**Online payments:** when you pay an invoice, our payment processor, Stripe, collects your payment details directly. We receive the payment confirmation, amount, invoice number, and the email address for your receipt. We never receive or store your full card number.',
        '**Communications:** emails, phone calls, support tickets, and anything you choose to share in them.',
        '**Server and security logs:** IP address, browser user-agent, requested page, referring page, date and time, and response status. We use these to operate the Site and to detect and block malicious traffic.',
        '**Site analytics (first-party):** pages viewed, time on page, scroll depth, links clicked, and basic device and browser characteristics: screen and window size, pixel density, time zone, preferred languages, light or dark display preference, touch support, connection type, page-load timing, and (where your browser provides it) operating-system version and device model. This data is processed on our own servers. We don’t use third-party advertising or analytics trackers.',
        '**Cookies:** one strictly necessary session cookie, `__Host-mrp.sid`, keeps your session secure and protects our forms against cross-site request forgery. It is HttpOnly, Secure and SameSite=Lax, and it expires after 24 hours. We don’t use advertising cookies.',
      ] },
    ] },
    { h: 'How we use information', blocks: [
      { list: [
        'To respond to your request and provide the assessment, quote or services you ask for.',
        'To create and secure your client portal account.',
        'To invoice, process payments, keep financial records, and meet tax and legal obligations.',
        'To protect the Site, our clients and PDI: detecting, investigating and blocking fraud, abuse and attacks (including automated blocking of malicious traffic).',
        'To understand which pages are useful and improve the Site.',
        'To send you service and account messages. We send marketing email only if you ask for it, and you can opt out at any time.',
      ] },
    ] },
    { h: 'AI tools', blocks: [
      'We may use AI tools to help summarize or route requests and draft documentation. These tools run on infrastructure PDI controls. We don’t submit your personal information to third-party AI services, and a person reviews anything that affects you.',
    ] },
    { h: 'How we share information', blocks: [
      'We share personal information only as described here:',
      { list: [
        '**Stripe**, to process online payments. Stripe’s use of your information is governed by the [Stripe Privacy Policy](https://stripe.com/privacy).',
        '**Google Fonts**, which serves the typefaces on our pages. When a page loads, your browser connects to Google’s servers, which receive your IP address. See the [Google Privacy Policy](https://policies.google.com/privacy).',
        '**Email and communications providers** that carry our messages. ⟦CONFIRM: name the provider, e.g., Microsoft 365 or GoDaddy⟧',
        '**Professional advisers** such as attorneys and accountants, under duties of confidentiality.',
        '**Legal and safety reasons:** to comply with law or legal process, or to protect the rights, property or safety of PDI, our clients or others.',
        '**Business transfers:** as part of a merger, acquisition or sale of assets, subject to this policy.',
        '**With your consent** or at your direction.',
      ] },
      '**We do not sell personal information, and we do not share it for targeted (cross-context behavioral) advertising.**',
    ] },
    { h: 'Your choices and rights', blocks: [
      'You can ask us to access, correct, delete or provide a copy of the personal information we hold about you, and to stop marketing messages. Portal users can also ask us to close their account. Email [admin@mrpearson.net](mailto:admin@mrpearson.net) with your request.',
      'We’ll verify your identity before acting, respond within 45 days ⟦CONFIRM⟧, and won’t treat you differently for exercising these choices. Some information we must keep for legal, tax, security or contractual reasons; we’ll tell you if that applies.',
      'We honor Global Privacy Control signals as a request not to sell or share personal information. We don’t sell or share it anyway.',
    ] },
    { h: 'How long we keep information', blocks: [
      { table: { head: ['Information', 'Retention'], rows: [
        ['Contact and assessment requests', '24 months after our last contact with you ⟦CONFIRM⟧'],
        ['Client portal accounts', 'For the life of the account, plus 90 days ⟦CONFIRM⟧'],
        ['Invoices, payment and billing records', '7 years, for tax and accounting purposes ⟦CONFIRM with CPA⟧'],
        ['Server and security logs', '90 days, longer when needed to investigate a security incident ⟦CONFIRM⟧'],
        ['Site analytics', '13 months ⟦CONFIRM⟧'],
      ] } },
    ] },
    { h: 'How we protect information', blocks: [
      'We use administrative, technical and physical safeguards appropriate to the information, including encrypted connections (HTTPS with HSTS), a strict Content-Security-Policy, access controls, and monitoring. No system is perfectly secure. If a security breach affects your personal information, we’ll notify you as required by law.',
    ] },
    { h: 'Where we process information', blocks: [
      'PDI is based in the United States and processes information on servers located in the United States ⟦CONFIRM⟧. If you use the Site from outside the U.S., your information will be processed in the U.S.',
    ] },
    { h: 'Children', blocks: [
      'The Site is intended for businesses and adults. It isn’t directed to children under 13, and we don’t knowingly collect their personal information. If you believe a child has given us information, contact us and we’ll delete it.',
    ] },
    { h: 'Changes to this policy', blocks: [
      'We’ll post any update here with a new effective date. If a change is material, we’ll give notice on the Site or by email before it takes effect.',
    ] },
    { h: 'Contact us', blocks: [
      'Pearson Digital Infrastructure LLC, 7027 Old Madison Pike NW, Suite 108, Huntsville, AL 35806 · [admin@mrpearson.net](mailto:admin@mrpearson.net) · (256) 675-9961',
    ] },
  ],
};

export const terms = {
  path: '/terms',
  title: 'Terms of Use',
  description: 'Terms governing use of mrpearson.net, the PDI client portal and online invoice payments, operated by Pearson Digital Infrastructure LLC.',
  intro: [
    `These Terms of Use ("Terms") govern your use of mrpearson.net, the PDI client portal, and online payments (together, the "Site"), operated by ${CO}.`,
    'By using the Site, you agree to these Terms. If you use the Site on behalf of an organization, you confirm that you have authority to accept these Terms for it. If you don’t agree, please don’t use the Site.',
  ],
  sections: [
    { h: 'Our services and your agreement with us', blocks: [
      'The Site describes PDI’s services. We provide professional services only under a signed Master Services Agreement, statement of work, proposal or other written agreement (a "Service Agreement"). If these Terms conflict with a Service Agreement, the Service Agreement controls.',
      'Information on the Site, including service descriptions, rates and service levels, is general information. It isn’t an offer you can accept by using the Site.',
    ] },
    { h: 'Rates and service levels', blocks: [
      'Published rates are current as of the Labor Rate Card version shown on our [pricing page](/pricing), and service levels as of the version shown on our [service levels page](/service-levels). We may update them. An update doesn’t change a signed Service Agreement except as that agreement allows.',
    ] },
    { h: 'No professional advice', blocks: [
      'Content about cybersecurity, compliance (including CMMC, NIST SP 800-171, SOC 2 and HIPAA) and technology is general information. It isn’t legal, accounting or compliance advice for your situation.',
      'PDI provides readiness and technical services. PDI does not certify organizations, and readiness work doesn’t guarantee the outcome of any assessment or audit.',
    ] },
    { h: 'Client portal accounts', blocks: [
      { list: [
        'You must be at least 18 and authorized by your organization to use the portal.',
        'Keep your credentials confidential and use multifactor authentication when it’s offered. You’re responsible for activity under your account.',
        'Tell us immediately at [admin@mrpearson.net](mailto:admin@mrpearson.net) or (256) 675-9961 if you suspect unauthorized access.',
        'We may suspend an account to protect the security of the Site, our clients or PDI, and we’ll tell you why when we can.',
      ] },
    ] },
    { h: 'Acceptable use', blocks: [
      'You agree not to:',
      { list: [
        'access, or attempt to access, accounts, systems or data you aren’t authorized to use;',
        'probe, scan or test the vulnerability of the Site, except as our [Security & Responsible Disclosure policy](/security) allows;',
        'interfere with or disrupt the Site, including denial-of-service attacks, flooding forms, or automated scraping that burdens the Site;',
        'upload malware or other malicious code;',
        'submit false, misleading or unlawful content, or impersonate any person or organization; or',
        'use the Site in violation of any law.',
      ] },
    ] },
    { h: 'Online payments', blocks: [
      'Online payments are processed by Stripe under Stripe’s terms. By paying, you authorize the charge for the amount you enter. PDI never receives or stores your full card number.',
      'If you have a question about a charge, please contact us before disputing it, so we can resolve it quickly.',
      'Refunds, cancellations and prepaid-block terms are set by your Service Agreement. Unless it says otherwise: ⟦CONFIRM proposed default: fees for services already performed are non-refundable; prepaid block balances expire 12 months after purchase and are non-refundable; duplicate or mistaken payments are refunded promptly after verification⟧.',
    ] },
    { h: 'Intellectual property', blocks: [
      'The Site and its content, including text, design, graphics and code, belong to PDI or its licensors. You may view and print pages for your own evaluation of PDI’s services. Any other copying, modification or redistribution requires our written permission.',
      'Third-party names that appear on the Site, such as Fortinet, Microsoft, Proxmox, Wazuh and others, are trademarks of their respective owners. They describe the technologies we work with and don’t imply endorsement, sponsorship or partnership.',
      'If you send us suggestions or feedback, we may use them without obligation to you.',
    ] },
    { h: 'Third-party links and services', blocks: [
      'The Site links to third-party websites and uses third-party services, such as Stripe. We aren’t responsible for their content, terms or privacy practices.',
    ] },
    { h: 'Disclaimers', blocks: [
      'The Site is provided "as is" and "as available." To the fullest extent permitted by law, PDI disclaims all warranties about the Site, express or implied, including merchantability, fitness for a particular purpose and non-infringement. We don’t warrant that the Site will be uninterrupted or error-free. This section doesn’t limit any warranty in a signed Service Agreement.',
    ] },
    { h: 'Limitation of liability', blocks: [
      'To the fullest extent permitted by law, PDI won’t be liable for any indirect, incidental, special, consequential or punitive damages, or for lost profits or lost data, arising from your use of the Site.',
      'PDI’s total liability for any claim arising from your use of the Site is limited to the greater of the amount you paid PDI through the Site in the 12 months before the claim, or one hundred U.S. dollars. ⟦CONFIRM with counsel⟧',
      'This section applies to use of the Site only. Liability for services is governed by your Service Agreement.',
    ] },
    { h: 'Indemnification', blocks: [
      'You agree to indemnify and hold PDI harmless from claims, losses and expenses (including reasonable attorneys’ fees) arising from your misuse of the Site or your violation of these Terms.',
    ] },
    { h: 'Governing law and disputes', blocks: [
      'These Terms are governed by the laws of the State of Alabama, without regard to its conflict-of-law rules. Before filing a claim, each party agrees to try to resolve the dispute informally for 30 days after written notice. Any lawsuit must be brought in the state or federal courts located in Madison County, Alabama, and both parties consent to their jurisdiction. ⟦CONFIRM venue with counsel⟧',
    ] },
    { h: 'General', blocks: [
      'We may update these Terms by posting a new version with a new effective date. Continued use of the Site after the update means you accept it.',
      'We may suspend or end access to the Site for anyone who violates these Terms. If any provision is unenforceable, the rest remains in effect. Our failure to enforce a provision isn’t a waiver. These Terms are the entire agreement about use of the Site, and you may not assign them without our consent.',
    ] },
    { h: 'Contact us', blocks: [
      'Pearson Digital Infrastructure LLC, 7027 Old Madison Pike NW, Suite 108, Huntsville, AL 35806 · [admin@mrpearson.net](mailto:admin@mrpearson.net) · (256) 675-9961',
    ] },
  ],
};

export const security = {
  path: '/security',
  title: 'Security & Responsible Disclosure',
  description: 'How to report a security vulnerability in mrpearson.net or the PDI client portal, the rules for good-faith research, and our safe-harbor commitment.',
  intro: [
    'Security is what we do, and we welcome reports of vulnerabilities in our own systems. If you believe you’ve found one, please tell us so we can fix it.',
  ],
  sections: [
    { h: 'How to report', blocks: [
      'Email [admin@mrpearson.net](mailto:admin@mrpearson.net) with the subject line "Security report". ⟦CONFIRM: consider a dedicated security@mrpearson.net mailbox⟧ Please include:',
      { list: [
        'a description of the issue and the affected URL or component;',
        'steps to reproduce it, with proof-of-concept details;',
        'the potential impact; and',
        'how to reach you for follow-up.',
      ] },
      'Share only the minimum data needed to demonstrate the issue. Our machine-readable contact file is at [/.well-known/security.txt](/.well-known/security.txt).',
    ] },
    { h: 'Scope', blocks: [
      '**In scope:** mrpearson.net and its pages, the PDI client portal, and the Site’s APIs.',
      '**Out of scope:** third-party services (for example Stripe and Google); systems PDI manages for its clients (report those to the client, or to us, without testing them); physical security; social engineering of PDI or its clients; and denial-of-service testing.',
    ] },
    { h: 'Rules for good-faith research', blocks: [
      { list: [
        'Test only against accounts you own or have permission to use.',
        'If you access anyone else’s data, stop, and report it immediately.',
        'Don’t exfiltrate, modify or delete data, and don’t keep data you encounter.',
        'Don’t run denial-of-service or high-volume automated scans.',
        'No phishing, social engineering or physical attempts.',
        'Give us reasonable time to fix the issue before any public disclosure: 90 days, or sooner by agreement ⟦CONFIRM⟧.',
        'Comply with all applicable laws.',
      ] },
    ] },
    { h: 'Our commitments', blocks: [
      { list: [
        'We’ll acknowledge your report within 3 business days.',
        'We’ll keep you updated on our progress and tell you when it’s fixed.',
        'With your permission, we’ll credit you publicly for the find.',
        'We don’t run a paid bug bounty.',
      ] },
    ] },
    { h: 'Safe harbor', blocks: [
      'If you make a good-faith effort to follow this policy, we’ll consider your research authorized, we won’t pursue or support legal action against you for it, and we’ll work with you to understand and resolve the issue. This doesn’t authorize testing of third-party systems. ⟦CONFIRM with counsel⟧',
    ] },
  ],
};

export const legalDocs = { privacy, terms, security };
