# Runbook: Disaster Recovery (site / platform failover)

**Scope:** loss of a primary host, cluster, or site (hardware failure, power, flood, ransomware at scale).
**Targets:** define per service — e.g. Tier-1 RTO 4h / RPO 1h, Tier-2 RTO 24h / RPO 24h.

> DR is only as good as the last test. Schedule a tabletop twice a year and one live failover a year.

## Before disaster (standing posture)

- Infrastructure is code: VMs rebuild from `terraform/` + `virtualization/*/pve-cloudinit-template.sh`,
  config from `ansible/playbooks/site.yml`. Keep these repos mirrored off-site.
- Backups follow 3-2-1 with a verified off-site encrypted copy (`runbooks/backup-and-restore.md`).
- A current, printed/offline copy of: this runbook, the asset inventory
  (`windows/Get-SystemInventory.ps1`, `virtualization/*/*inventory*`), IP plan, and emergency contacts.
- Secrets recoverable from the password manager / vault with a documented break-glass procedure.

## Declaration

1. The IC declares a disaster and the target recovery site/platform.
2. Start the DR timeline (scribe). Notify stakeholders with an initial ETA.

## Recovery order (dependencies first)

1. **Network & identity:** restore the management network, DNS, DHCP, and a domain controller
   (`identity/active-directory/New-ADForest.ps1` for a clean rebuild, or restore a DC system-state backup).
   Nothing else authenticates until this is up.
2. **Platform:** stand up the hypervisor/cluster; restore or re-provision the VM templates.
3. **Data tier:** restore databases/file servers to the chosen RPO; verify integrity before dependents start.
4. **Application tier:** deploy from IaC (`terraform apply`, `kubectl apply -k` /
   `helm upgrade --install`), point at the restored data.
5. **Edge:** DNS cutover (lower TTLs in advance), firewall/reverse-proxy, TLS certs
   (`runbooks/certificate-renewal.md`), then re-enable public access.

## Validate

- [ ] Authentication works (a test user logs in; Kerberos/LDAP healthy —
      `identity/active-directory/Get-ADHealthReport.ps1`).
- [ ] Each Tier-1 service passes an end-to-end transaction.
- [ ] Monitoring and alerting are running at the DR site (don't fly blind).
- [ ] Record actual RTO/RPO achieved per service.

## Failback (after the primary is restored)

Reverse the process deliberately, during a planned window: re-sync data from DR → primary, validate,
cut DNS back, then decommission the temporary DR resources. Do not rush failback; a botched failback
causes a second outage.

## After-action

Document gaps (missing dependency, slow restore, stale runbook step) and fix them while fresh. Update
RTO/RPO commitments if the test proved them unrealistic.
