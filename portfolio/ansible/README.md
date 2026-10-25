# ansible

A small collection of hardening/automation roles plus playbooks. Passes `ansible-lint` (production
profile), `yamllint` and `--syntax-check` in CI. Install dependencies:

```bash
ansible-galaxy collection install -r requirements.yml -p ./collections
```

## roles

| Role | What it does |
|---|---|
| `baseline` | Packages, timezone, chrony, admin accounts + SSH keys (exclusive), sudo, login banners, sysctl hardening, journald caps. Debian/RHEL/SUSE. |
| `ssh_hardening` | OpenSSH drop-in validated with `sshd -t` before install; modern KEX/ciphers/MACs filtered to what the host supports; SELinux port handling. |
| `firewall` | ufw or firewalld; SSH restricted to management networks; public and source-restricted service rules. |
| `docker` | Docker Engine from the vendor repo with a hardened `daemon.json`. |
| `node_exporter` | Prometheus node_exporter from the checksum-verified release, in a sandboxed systemd unit. |
| `windows_baseline` | SMB/SCHANNEL/RDP-NLA/firewall/audit-policy baseline for Windows Server. |

## playbooks

`site.yml` (apply roles per group), `patch-linux.yml` (rolling, one host at a time, health-gated),
`network-backup.yml` (pull Cisco IOS + FortiGate configs; needs `cisco.ios` and `fortinet.fortios`).

```bash
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/patch-linux.yml --limit web -e reboot=true
```
