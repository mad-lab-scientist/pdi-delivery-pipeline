# virtualization

Automation for the four hypervisor platforms a DevOps/infra architect commonly runs.

## proxmox (Bash, `pvesh`/`qm`)
| Script | What it does |
|---|---|
| `pve-vm-inventory.sh` | Cluster-wide VM/CT inventory (CPU/RAM/disk/uptime/tags) as table/CSV/JSON. |
| `pve-cloudinit-template.sh` | Build a cloud-init VM template from an official image, **checksum-verified** against the vendor's published sums. |
| `pve-clone-vm.sh` | Deploy a VM from a template with static IP/gateway/DNS, sizing, VLAN; waits for the guest agent. |
| `pve-backup-report.sh` | Are all guests actually backed up? Newest backup per guest, coverage gaps, PBS verification, failed jobs. |
| `pve-snapshot-cleanup.sh` | Find (and optionally delete) old snapshots across the cluster, with a keep-pattern. |

## vmware (PowerShell / PowerCLI)
`Get-VMInventoryReport.ps1`, `Get-VMSnapshotReport.ps1` (snapshots are not backups), `New-VMFromTemplate.ps1`
(guest customization, static IP, Linux/Windows), `Get-ESXiSecurityReport.ps1` (vSphere Security Config Guide checks).

## hyper-v (PowerShell / Hyper-V module)
`New-HyperVVM.ps1` (Gen2, Secure Boot, optional vTPM, VLAN, DHCP/Router guard), `Get-HyperVHostReport.ps1`
(capacity, integration services, checkpoints, replication health).

## nutanix (Python, Prism Central v3 REST)
`nutanix_inventory.py` — clusters, hosts and every VM via the paginated v3 API; TLS-verified; stdlib only.
