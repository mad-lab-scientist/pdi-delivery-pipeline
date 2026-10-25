# network

Dependency-free Python network and security tools (Python 3.12, standard library only). Unit tests in
`tests/` (`python -m unittest`).

| Tool | What it does |
|---|---|
| `subnet_planner.py` | VLSM subnet planner: carve a parent block into right-sized subnets (largest-first, no gaps), with gateway/range/broadcast and free-space report. Interactive or CLI. |
| `port_scan.py` | Async TCP connect scanner with optional banner grabbing; refuses public targets without `--authorized`. |
| `ping_sweep.py` | Find live hosts in a subnet (uses the OS ping, no root), with reverse DNS. |
| `tls_audit.py` | TLS endpoint audit: chain validity, expiry, hostname match, protocol support; Nagios-style exit codes for monitoring. |
| `dns_audit.py` | DNS + email-security audit (NS/MX/SPF/DMARC/DKIM/CAA/DNSSEC/MTA-STS) with its **own DNS wire-protocol client** — no dependencies. |
| `fortigate_audit.py` | FortiGate config auditor: risky policies, shadowed rules, exposed management, weak crypto, SSL-VPN on WAN. |
| `cisco_ios_audit.py` | Cisco IOS/IOS-XE hardening audit against CIS-style controls, with a remediation command per finding. |
| `device_backup.py` | Multi-vendor config backup over SSH (Netmiko) with change detection (ignores volatile lines) and optional git history. |
| `syslog_receiver.py` | Lightweight UDP/TCP syslog collector (RFC 5424/3164 + FortiGate key=value) to daily JSON lines. |

Examples:

```bash
python subnet_planner.py 10.20.0.0/16 users=500 servers=120 voice=200 mgmt=20 --p2p-31
python dns_audit.py example.com --dkim google,selector1 --resolver 1.1.1.1
python fortigate_audit.py FGT60F_backup.conf --format markdown
```
