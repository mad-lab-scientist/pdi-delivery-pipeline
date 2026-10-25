# kali — authorized assessment tooling

Tooling for **authorized, scoped** security assessments. The design principle is simple: staying in scope
is the default, enforced in code. Every tool loads an engagement scope and refuses to act on anything that
is not explicitly in scope, inside the authorized time window, and not on the exclusion list.

> Only test systems you are contractually authorized to test. Unauthorized scanning or access is illegal
> in most jurisdictions (e.g. the US Computer Fraud and Abuse Act). These tools will refuse out-of-scope
> targets, but they cannot grant you authorization — that comes from a signed Authorization to Test / SOW.

## Files

| File | What it does |
|---|---|
| `lib/scope.py` | Loads and validates the engagement scope; the authorization gate used by every tool. Run `python lib/scope.py scope.yaml --check <target>` to test a target. |
| `recon.py` | Scope-gated nmap orchestrator. Refuses out-of-scope targets, limits nmap to host discovery and service/version detection with `default,safe` scripts only, and rejects intrusive/exploit/DoS/brute script categories by design. Requires `--i-am-authorized` to run. |
| `parse_nmap.py` | Turns nmap XML into a service inventory and a notable-exposure summary (markdown/CSV). Pure parsing; runs no scans. |
| `scope.example.yaml` | Example engagement scope with a complete authorization record (documentation-range addresses). |

## Workflow

```bash
# 1. Write the scope from the signed authorization.
cp scope.example.yaml engagements/acme.yaml && $EDITOR engagements/acme.yaml

# 2. Confirm the scope parses and the window is active; spot-check a target.
python lib/scope.py engagements/acme.yaml --check 192.0.2.50

# 3. Dry-run to see exactly what would be scanned (nothing is sent).
python recon.py --scope engagements/acme.yaml --targets 192.0.2.0/24 --top-ports 200 --dry-run

# 4. Run it (requires nmap and explicit authorization acknowledgement).
python recon.py --scope engagements/acme.yaml --targets 192.0.2.0/24 --top-ports 200 --i-am-authorized

# 5. Report.
python parse_nmap.py engagements/PDI-2026-014/recon-*.xml --format markdown > findings.md
```

## What these tools deliberately do not do

No exploitation, no password brute-forcing, no denial-of-service, no detection evasion. `recon.py` hard-codes
nmap's `default,safe` script set and rejects any attempt to add intrusive categories. For deeper, authorized
testing, use purpose-built tooling under the same scope discipline and rules of engagement.
