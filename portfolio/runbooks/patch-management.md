# Runbook: Patch Management

**Scope:** routine and emergency patching of Linux, Windows and network devices.
**Goal:** patched within policy (security updates ≤ 30 days; actively-exploited/KEV ≤ 7 days or faster),
with no self-inflicted outages.

## Cadence

| Class | Window | Policy |
|---|---|---|
| Linux/Windows security updates | Monthly maintenance window | within 30 days of release |
| Known-exploited (CISA KEV) / CVSS ≥ 9 under attack | Emergency change | within 72 hours, often sooner |
| Firmware (FortiGate, BIOS) | Scheduled, change-controlled | per vendor EoS / advisory |

## Pre-patch

1. Confirm backups/snapshots are current (`runbooks/backup-and-restore.md`).
2. Review what will change:
   - Linux: `linux/<family>/*-maintenance.sh --check` (apt/dnf/zypper) — lists updates, security count, reboot need.
   - Windows: `windows/Get-PatchCompliance.ps1` — missing updates, criticality, pending reboot.
3. Announce the window to stakeholders; note rollback plan (snapshot revert).

## Execute (rolling, never all-at-once for a service group)

- **Linux fleet:** `ansible-playbook ansible/playbooks/patch-linux.yml --limit <group> -e reboot=true`
  — `serial: 1` patches one host at a time; `max_fail_percentage: 0` halts the run if any host fails,
  so a bad patch stops before it hits the whole group.
- **Single Linux host:** `sudo bash linux/<family>/<apt|dnf|zypper>-maintenance.sh --reboot 5`.
- **Windows:** patch through WSUS/SCCM/Intune or Ansible `ansible.windows.win_updates`; reboot in the window.
- **FortiGate firmware:** follow the vendor upgrade path (never skip major versions); take a config
  backup first (`ansible/playbooks/network-backup.yml`); upgrade the secondary in an HA pair first.

## Post-patch verification

- [ ] Host booted and all services healthy (`linux/common/system-health.sh`, synthetic checks green).
- [ ] The specific CVE/update is actually applied (don't assume — spot-check package/KB version).
- [ ] No new failed units / event-log errors.
- [ ] Monitoring stable for the agreed soak time before declaring success.

## Rollback

- VM: revert to the pre-patch snapshot (fastest).
- Package: pin/downgrade the offending package, hold it, and open a ticket to unblock the update.
- Document why a patch was held so it is revisited, not forgotten.

## Emergency patch (KEV / active exploitation)

1. Open an emergency change; IC approves verbally, documented after.
2. Assess exposure first — is the vulnerable service even reachable? (host firewall, `network/port_scan.py`
   against your own authorized ranges). Mitigate immediately (block the port / disable the feature) even
   before the patch lands.
3. Patch the most-exposed systems first (internet-facing), then internal.
4. Confirm the fixed version everywhere; close the change with the list of patched assets.
