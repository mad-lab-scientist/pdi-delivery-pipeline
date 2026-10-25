# Infrastructure & Security Engineering Toolkit

A working toolkit by a DevOps / Security / Network Architect: real scripts, modules, pipelines and
runbooks used to build, secure, automate and operate on-prem and cloud infrastructure. Nothing here is
pseudo-code — every tool runs, and the whole repository is linted and tested in CI (see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

> Addresses use documentation ranges (RFC 5737 `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) and
> example domains (RFC 2606 `example.com`). Replace them with your own. Scripts that make changes support
> `--dry-run`/`-WhatIf` and validate input before acting.

## What's inside

| Area | Path | Highlights |
|---|---|---|
| **Network engineering** | [`network/`](network/) | VLSM subnet planner, async port scanner, dependency-free DNS/email-security auditor (SPF/DMARC/DKIM/DNSSEC), TLS auditor, FortiGate & Cisco IOS config auditors, multi-vendor config backup, syslog collector |
| **Linux administration** | [`linux/`](linux/) | Cross-distro (Debian/Ubuntu, RHEL/Rocky, SUSE) baseline hardening, static-IP with auto-rollback, health check, LVM growth, user audit, per-distro patching, firewalld & SELinux helpers |
| **Windows & Active Directory** | [`windows/`](windows/), [`identity/`](identity/) | CIS-aligned server hardening, system inventory, security-event & patch-compliance reporting; AD forest build, tiered OU model, bulk user import, AD health & security report, stale-account cleanup, DHCP/DNS automation, Linux-to-AD join |
| **Virtualization** | [`virtualization/`](virtualization/) | Proxmox (cloud-init templates, clone, backup & snapshot audits), VMware/vSphere (PowerCLI inventory, snapshot & ESXi-security reports, deploy-from-template), Hyper-V (Gen2 VM build, host report), Nutanix (Prism v3 inventory) |
| **Infrastructure as Code** | [`terraform/`](terraform/) | Reusable modules: AWS VPC (multi-AZ, NAT, flow logs), Azure hub network, GCP VPC + Cloud NAT, Proxmox VM; example environments |
| **Configuration management** | [`ansible/`](ansible/), [`config-management/`](config-management/) | Ansible collection of hardening roles (baseline, ssh, firewall, docker, node_exporter, windows) + playbooks; equivalent Puppet profile and Chef cookbook |
| **Cloud** | [`cloud/`](cloud/) | AWS security-posture audit (boto3, CIS-mapped), Azure NSG and GCP firewall exposure audits |
| **CI/CD** | [`cicd/`](cicd/) | GitLab CI, Jenkins declarative pipeline, Azure Pipelines — lint → test → build+scan → gated deploy |
| **Containers & orchestration** | [`containers/`](containers/), [`nginx/`](nginx/) | Hardened Dockerfile, Docker Compose monitoring stack, Kubernetes manifests (securityContext, NetworkPolicy, PDB, HPA) + Kustomize + Helm chart, nginx reverse proxy |
| **Observability** | [`observability/`](observability/) | Prometheus scrape config + alert rules, Alertmanager routing, Grafana provisioning |
| **Operational runbooks** | [`runbooks/`](runbooks/) | Incident response, backup & restore, patch management, disaster recovery, certificate renewal, user on/offboarding |
| **Authorized assessment** | [`kali/`](kali/) | Scope-gated reconnaissance for sanctioned engagements — refuses out-of-scope targets by design |

## Languages & tools

Python 3.12 · Bash · PowerShell 7 · Terraform (HCL) · Ansible · Puppet · Chef · Docker · Kubernetes ·
Helm · Prometheus · nginx · AWS · Azure · GCP · Proxmox · VMware · Hyper-V · Nutanix · Cisco IOS ·
FortiGate.

## Everything here is tested

The CI workflow runs on every push and must pass:

| Check | Covers |
|---|---|
| `ruff` + `python -m unittest` | all Python (25 unit tests: subnet math, DNS wire format, SPF/DMARC, config auditors, scope gating, nmap parsing) |
| `shellcheck` | every Bash script |
| `PSScriptAnalyzer` + `Pester` | every PowerShell script (NetTools module unit tests) |
| `yamllint` | all YAML |
| `terraform fmt` + `terraform validate` | all Terraform modules and environments |
| `ansible-lint` + `--syntax-check` | all roles and playbooks |
| `puppet parser validate`, Ruby `-c` | Puppet manifests, Chef recipes |
| `promtool` | Prometheus config and alert rules |
| `kustomize` + `kubeconform`, `helm lint`/`template` | Kubernetes manifests and the Helm chart |
| `hadolint` | Dockerfiles |

Run the Python suite locally:

```bash
cd network/tests && python -m unittest        # network tools
cd kali/tests    && python -m unittest        # authorized-assessment tools
```

## Design principles

- **Safe by default.** Change-making scripts preview with `--dry-run` / `-WhatIf`, validate input, and
  back up or roll back (the static-IP tools schedule an automatic rollback before applying).
- **Idempotent.** Re-running converges; it doesn't duplicate or thrash.
- **Least privilege & defense in depth.** Hardening follows CIS / NIST guidance; firewalls default-deny;
  secrets come from vaults/stores/files, never from the code.
- **Cross-platform where it matters.** One Linux script spans Debian, RHEL and SUSE families; one Ansible
  role covers them all.

## License

© Pearson Digital Infrastructure LLC. Published as a work sample; not licensed for reuse.
