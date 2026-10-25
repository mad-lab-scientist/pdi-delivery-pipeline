# Runbook: Backup & Restore

**Scope:** verifying backups and performing restores for VMs and application data.
**Principle:** a backup you have never restored is a hypothesis, not a backup. Test restores on a schedule.

## Backup health check (run weekly)

| Platform | Command | Pass criteria |
|---|---|---|
| Proxmox | `virtualization/proxmox/pve-backup-report.sh --max-age 2` | exit 0; every guest covered, newest < 2 days, PBS verification not failed |
| vSphere | check the backup product + `virtualization/vmware/Get-VMSnapshotReport.ps1` (snapshots are **not** backups) | no snapshot older than a few days masquerading as a backup |
| Databases | application-native dump + checksum | dump completes, checksum recorded |

The 3-2-1 rule: **3** copies, on **2** media types, **1** off-site. The platform backups are copy 1–2;
the off-site encrypted copy is copy 3 (`.gpg`, pulled to a separate failure domain).

## Restore decision

1. Identify the restore point **before** the data loss / compromise window.
2. Decide restore target: in place (fast, risky) vs. a new/isolated VM (safe — preferred for incident
   recovery, so you can validate before cutover).
3. Record RPO (how much data you will lose) and estimated RTO (time to restore) in the ticket.

## Proxmox VM restore

```bash
# List restore points for a VM (replace node/storage/vmid)
pvesh get /nodes/<node>/storage/<store>/content --content backup --output-format json \
  | jq -r '.[] | select(.vmid==<vmid>) | "\(.volid)  \(.ctime|todate)  \(.size)"' | sort

# Restore to a NEW vmid first (does not overwrite the running guest)
qmrestore <storage>:backup/vzdump-qemu-<vmid>-<timestamp>.vma.zst <new-vmid> --storage <target-store>

# Validate the new VM, then cut over (stop old, reassign IP/MAC or re-run cloud-init), then retire the old.
```

For encrypted off-site copies: decrypt first (`gpg --output restore.vma.zst --decrypt copy.vma.zst.gpg`),
verify the sha256 against the recorded value, then restore.

## Application data / database restore

1. Stop the application (or put it in maintenance mode) to avoid writes during restore.
2. Restore the dump to a scratch database first; run integrity checks and a row-count sanity check.
3. Swap the restored database in; start the application; verify with a smoke test.

## Post-restore verification (always)

- [ ] Service answers its health check and a real transaction works end to end.
- [ ] File ownership/permissions correct (restores often land as root — see the web3 backup script's
      ownership checks for the pattern).
- [ ] Data current to the expected restore point; no gaps.
- [ ] Monitoring green; no error-log spike.
- [ ] Record actual RPO/RTO achieved vs. target — feed misses back into the backup design.

## Quarterly: a real restore test

Pick one production system per quarter and restore it to an isolated VLAN. Time it. If RTO exceeds the
SLA commitment, fix the bottleneck (backup size, network, process) before it matters in a real event.
