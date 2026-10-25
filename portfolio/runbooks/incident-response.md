# Runbook: Security Incident Response

**Scope:** suspected compromise, malware, data exposure, or unauthorized access on PDI-managed systems.
**Audience:** on-call engineer and the incident commander (IC).
**Aligned with:** NIST SP 800-61r2 (Preparation → Detection & Analysis → Containment, Eradication & Recovery → Post-incident).

> Do not power off a suspected-compromised host unless it is actively causing harm — you lose volatile
> evidence (memory, network state). Isolate instead.

## 0. Roles (assign in the first 5 minutes)

| Role | Responsibility |
|---|---|
| Incident Commander | Decisions, scope, comms; keeps the timeline |
| Technical lead | Executes containment/eradication |
| Scribe | Timestamps every action in the incident ticket |
| Comms | Internal/customer/regulator notifications |

## 1. Detect & triage (first 15 minutes)

1. Open an incident ticket; record the reporting source and the time (UTC).
2. Classify severity:
   - **SEV-1** active data exfiltration, ransomware, domain-admin compromise, customer data exposure.
   - **SEV-2** single-host compromise, contained malware, credential theft (one account).
   - **SEV-3** policy violation, isolated phishing click with no follow-on.
3. Pull quick signals:
   - Windows auth events: `windows/Get-SecurityEventReport.ps1 -Hours 24` on affected hosts and DCs.
   - Host health / unexpected listeners: `linux/common/system-health.sh` (section "listening").
   - Firewall/VPN probes and egress spikes from FortiGate logs.

## 2. Contain

- **Network isolation (preferred):** move the host to a quarantine VLAN or apply a deny-all firewall
  policy that still allows your forensic access. On the FortiGate, confirm no unexpected inbound allow
  (`network/fortigate_audit.py <backup.conf>`).
- **Account containment:** disable, do not delete, the affected accounts.
  - AD: `identity/active-directory/Disable-StaleADAccounts.ps1` pattern, or `Disable-ADAccount` directly;
    then rotate the account's password and revoke Kerberos tickets.
  - **If domain admin is suspected: rotate the `krbtgt` password twice** (10+ hours apart) — see
    `identity/active-directory/Get-ADHealthReport.ps1` for the current krbtgt age.
- **Credential rotation:** any secret the host could read (service accounts, API tokens, SSH keys).
- Snapshot the VM (Proxmox/vSphere/Hyper-V) **before** eradication to preserve evidence.

## 3. Eradicate & recover

1. Rebuild from a known-good image rather than cleaning in place where feasible
   (`virtualization/proxmox/pve-clone-vm.sh` or your template pipeline).
2. Patch the exploited vulnerability before returning the host to service
   (`linux/*/*-maintenance.sh`, `windows/Get-PatchCompliance.ps1`).
3. Restore data from a backup taken **before** the compromise window
   (`runbooks/backup-and-restore.md`).
4. Re-baseline the host: `ansible-playbook ansible/playbooks/site.yml --limit <host>`.
5. Reset and re-enable accounts; require password change at next logon.

## 4. Verify before closing

- [ ] Attacker access removed (no rogue accounts, scheduled tasks, services, SSH keys —
      `linux/common/user-audit.sh`, `windows/Invoke-ServerHardening.ps1` audit mode).
- [ ] Indicators of compromise blocked at the firewall and EDR.
- [ ] Monitoring confirms normal behavior for 24–72h.
- [ ] All rotated credentials confirmed working; old ones invalid.

## 5. Post-incident (within 5 business days)

- Blameless review: timeline, root cause, what detection/controls would have caught it earlier.
- File action items (detections, hardening, training) with owners and dates.
- If customer data or regulated data was involved, trigger the breach-notification clock per contract
  and law (the MSA specifies a 24-hour breach-notice to affected customers).

## Evidence handling

Store memory/disk images and logs in a restricted, access-logged location. Keep a chain-of-custody note
for each artifact (who collected it, when, from where, hash). Never analyze the only copy.
