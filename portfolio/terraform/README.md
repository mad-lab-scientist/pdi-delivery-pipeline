# terraform

Reusable modules and example environments (Terraform ≥ 1.6). Every module and environment passes
`terraform fmt -check` and `terraform validate` in CI.

## modules

| Module | What it builds |
|---|---|
| `aws-vpc` | Production VPC: public/private subnets across 2–3 AZs, internet gateway, optional NAT gateways (HA or single), optional VPC flow logs to CloudWatch with a least-privilege role. Subnets derived with `cidrsubnet`. |
| `azure-network` | Resource group + VNet + subnets, a default-deny NSG (management allowed only from named sources), optional NSG flow logs. |
| `gcp-network` | Custom-subnet VPC with optional GKE secondary ranges and flow logs, firewall rules (allow-internal, allow-SSH-from-trusted, explicit deny), optional Cloud NAT. |
| `proxmox-vm` | Clone a VM from a cloud-init template (bpg/proxmox) with sizing, VLAN, static IP and cloud-init users. |

## environments

`prod-aws/` (S3 backend, the AWS VPC module) and `lab-proxmox/` (two VMs from a template via `for_each`)
show how the modules are consumed. Backends and credentials come from the environment / CI, never the repo.

```bash
cd environments/prod-aws
terraform init -backend-config=backend.hcl
terraform plan
```
