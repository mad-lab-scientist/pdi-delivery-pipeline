# PDI delivery pipeline: the source behind mrpearson.net

This is the public half of how [Pearson Cyber Defense](https://mrpearson.net) ships its website. It holds the site's
source and the release-pipeline tooling, published so prospects and partners can see exactly how it is built and checked.
The application, admin portal, infrastructure and deployment scripts stay in a private repository and on an internal
network. Live results: **[mrpearson.net/engineering](https://mrpearson.net/engineering)**.

## What is here
| Path | What it is |
|---|---|
| `website/` | The site: a zero-dependency Node static build with CSP-safe markup, WCAG AA contrast and page-weight budgets |
| `website/test/run-tests.mjs` | The site's test suite: truth guards (only approved prices, no withdrawn claims), CSP, links, accessibility, budgets, no internal details, and the pipeline-record contract |
| `ci/` | The release-pipeline runner (`run.mjs`), stage definitions, the repository secret scan and the SBOM/audit stage |
| `Jenkinsfile` | The Jenkins pipeline: one stage per pipeline stage, ending in a human approval |
| `.github/workflows/ci.yml` | This repository's own CI: build, test suite and secret scan on every push, with actions pinned to commit SHAs |

## The release pipeline
Every release of mrpearson.net passes these stages before it can be deployed. Stages marked *private* run against
the application source in the private repository.

| # | Stage | What it proves | Here |
|---|---|---|---|
| 1 | Facts & claims | Prices, service levels, CMMC dates and NAICS codes are cross-checked against the source documents. Banned or unprovable claims, broken links, weak contrast, page weight and the content security policy are checked too. | yes |
| 2 | Build from source | Every change is applied as an exact, counted patch to the recorded application source. Any drift stops the build. | private |
| 3 | Release integrity | Only intended files changed, file encodings are preserved, retired features are fully gone, and no secrets or internal details ship. | private |
| 4 | Live application test | The built application runs in production mode and is driven end to end: public site, forms, client portal, every admin page, data retention and rate limits. | private |
| 5 | Secret scan | The whole repository is scanned for credentials and private keys. | yes |
| 6 | Dependencies & SBOM | A CycloneDX software bill of materials is generated from the lockfile, and the release is blocked on any high or critical advisory. | private |
| 7 | Deploy rehearsal | The real deploy, rollback, web-server and backup scripts run against a production look-alike (Ubuntu 24.04, nginx 1.24, Node 24), including injected failures that must roll back on their own. | private |

Latest published run: **local-20261025-025611**, passed, 265/265 checks, release v3.2.0.

## Controls mapping (NIST SP 800-171 Rev. 2)
| Requirement | How the pipeline supports it |
|---|---|
| **3.4.1** Establish and maintain baseline configurations and inventories of organizational systems (including hardware, software, firmware, and documentation) throughout the respective system development life cycles. | Recorded source snapshot, archived release builds with file manifests, and an SBOM per release. |
| **3.4.2** Establish and enforce security configuration settings for information technology products employed in organizational systems. | Security headers and the web-server configuration are generated and verified; repository-wide secret scan. |
| **3.4.3** Track, review, approve or disapprove, and log changes to organizational systems. | Every change is a reviewed patch file; the owner approves by running the deploy; deploy logs are kept. |
| **3.4.4** Analyze the security impact of changes prior to implementation. | The full test chain and a deploy rehearsal must pass before anything reaches production. |
| **3.4.5** Define, document, approve, and enforce physical and logical access restrictions associated with changes to organizational systems. | Only the owner can deploy, and the admin console is reachable only from PDI’s internal network. |
| **3.14.1** Identify, report, and correct system flaws in a timely manner. | Dependency advisories are checked on every run and high or critical findings block the release. |

## Run it
Requires Node.js 22.13 or newer.
```bash
node website/build.mjs                                  # builds website/dist
PDI_PUBLIC_SHOWCASE=1 node website/test/run-tests.mjs   # the test suite (showcase mode)
node ci/scan-secrets.mjs                                # repository secret scan
node website/preview.mjs                                # local preview on http://localhost:4173
```
In showcase mode, the tests that compare the site against PDI's internal source documents (rate-card derivation,
playbooks) are reported as skipped. In the private repository they run and must pass.

## Honesty rules (enforced by the tests)
- Prices, service levels and dates on the site must match the source documents, and the test suite fails on any unapproved dollar figure or withdrawn claim.
- The engineering page shows only recorded pipeline runs, built field by field from an allow-list. It never shows logs.
- No claim of automatic deployment: production changes are approved by a person and applied by scripts that preflight and roll back on their own.

## License
© Pearson Digital Infrastructure LLC. All rights reserved. The source is published for transparency, not licensed for reuse.
