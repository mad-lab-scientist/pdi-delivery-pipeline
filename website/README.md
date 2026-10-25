# mrpearson.net v2: public site

A zero-dependency static build of the public pages of mrpearson.net (Pearson Cyber Defense). Every price, service level and CMMC fact comes from the authoritative files in `knowledge/`. The test suite fails if the site drifts from them.

```powershell
node website/build.mjs            # build into website/dist/
node website/test/run-tests.mjs   # 20 checks; must say "0 failed"
node website/preview.mjs          # http://127.0.0.1:4173 (mock API; nothing is sent anywhere)
```

## Layout
| Path | What it is |
|---|---|
| `src/content/site.mjs` | Company facts, principles, delivery model, lab, NAICS. Source: `knowledge/pdi-company-core/01-company-profile.md`, Government Contracting Playbook |
| `src/content/pricing.mjs` | Labor Rate Card v1.0: tiers, rate per service, premiums, block hours, market references. Source: `knowledge/pdi-company-core/08-labor-rate-card.md` |
| `src/content/sla.mjs` | SLA v2.0. Source: `knowledge/pdi-company-core/04-sla-and-priority-matrix.md` |
| `src/content/defense.mjs` | CMMC facts. Source: `knowledge/pdi-executive-playbooks/03-cmmc-2-readiness-playbook.md` |
| `src/content/services.mjs` | The 13 service lines (scope, deliverables, fit, FAQ). No prices here |
| `src/templates/` | `layout.mjs` (head, header, footer) and `pages.mjs` (every page) |
| `src/assets/` | `css/site.css` (design system), `js/site.js` (nav, forms, CSRF, countdown), `js/network.js` (hero animation), `img/favicon.svg` |
| `test/run-tests.mjs` | Fact parity, truth guards, CSP, structure, links, drafts, IP/secret scan, contrast, budgets |

## Rules
1. **Change a fact in `knowledge/` first**, then in `src/content/`. The tests compare the two.
2. **No dollar amount** may appear unless it's a rate-card figure, a computed block example, a sourced market range, a NAICS size standard, or the $25 invoice minimum. Legacy plan prices stay retired.
3. **No 24/7, "unlimited", "certified" or live-statistic claims** unless the sentence states the limitation. The tests check every sentence, list item and table cell.
4. **CSP-safe:** no inline scripts, `on*=` handlers or `style=` attributes. Scripts load only from `/assets/`.
5. Legal pages (`/privacy`, `/terms`) are **drafts**. They build to `dist/_drafts/`, stay out of the sitemap and nav, and carry `noindex`. To publish one, remove `draft: true` in `pages.mjs` after the Owner and counsel approve it.

## Compatibility with the running site
The forms call the **existing** mrpearson.net API exactly as the current `main.js` does:
- `GET /api/csrf-token` (used when the page has no server-rendered token)
- `POST /api/contact` with `{name, email, company, service, message, sourcePage}`
- `POST /api/checkout` with `{planKey: "custom-invoice", invoiceNumber, amount, email, _csrf}`. The client only redirects to `https://checkout.stripe.com/...`
- `POST /api/analytics/event` with `{eventType, label, path}` (no personal data in labels)

Not ported yet: the page-view beacon (`/api/analytics/view` with a server-issued `pv-token`). It needs the server code to match the payload exactly. App routes (`/login`, `/register`, `/app`, `/admin`, `/api/*`) stay on the Node app. Deployment and integration: `docs/10-website-overhaul.md`.
