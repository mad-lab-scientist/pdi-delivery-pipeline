# linux

Cross-distribution Bash administration and hardening scripts. `lib/common.sh` provides shared logging,
OS detection (Debian/Ubuntu, RHEL/Rocky/Alma, SUSE, Alpine, Arch), input validation, prompts and a
`--dry-run` facility. All scripts pass `shellcheck -x`.

| Script | What it does |
|---|---|
| `common/server-baseline.sh` | Secure baseline for a new server: hostname/timezone, chrony, admin user + SSH key, SSH hardening (validated with `sshd -t`), host firewall limited to a management network, automatic security updates, sysctl hardening, auditd. Refuses to lock you out. |
| `common/configure-static-ip.sh` | Static IPv4 across netplan / NetworkManager / ifupdown / wicked, with a scheduled **automatic rollback** if the gateway stops answering. |
| `common/system-health.sh` | One-screen health check (load, memory, disks/inodes, failed units, NTP, pending updates, reboot) with Nagios exit codes. |
| `common/lvm-extend.sh` | Grow an LV and its filesystem after a disk resize (rescan → growpart → pvresize → lvextend). |
| `common/user-audit.sh` | Local account & privilege review: UID-0 accounts, empty passwords, sudo/NOPASSWD, SSH keys (weak keys flagged), stale logins. |
| `debian-ubuntu/apt-maintenance.sh`, `rhel-rocky/dnf-maintenance.sh`, `suse/zypper-maintenance.sh` | Per-distro patching with `--check`, security-only, and reboot handling (Snapper snapshots on SUSE). |
| `rhel-rocky/firewalld-zone-setup.sh` | Build a firewalld zone for a role, bound to source networks, with validated services/ports. |
| `rhel-rocky/selinux-report.sh` | Explain recent SELinux denials and the right fix (boolean / fcontext / port) instead of `setenforce 0`. |

Every change-making script supports `--dry-run` and `--yes`.
