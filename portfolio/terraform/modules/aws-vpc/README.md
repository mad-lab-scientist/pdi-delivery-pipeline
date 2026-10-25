# aws-vpc

A production-ready AWS VPC: public and private subnets across 2–3 Availability Zones, an internet
gateway, optional NAT gateways (one per AZ for HA, or a single shared one), and optional VPC flow logs
to CloudWatch with a least-privilege IAM role.

## Usage

```hcl
module "vpc" {
  source     = "../../modules/aws-vpc"
  name       = "prod"
  cidr_block = "10.40.0.0/16"
  az_count   = 2

  enable_nat_gateway = true
  single_nat_gateway = false # true for non-prod to save cost
  enable_flow_logs   = true

  tags = {
    Environment = "prod"
    Owner       = "platform-team"
  }
}
```

Subnets are derived from the VPC CIDR with `cidrsubnet(cidr, 4, n)`: public subnets take index `0..az_count`,
private subnets `8..8+az_count`, so a `/16` yields `/20` subnets with room to add tiers later.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Name prefix for all resources |
| `cidr_block` | string | — | VPC CIDR (prefix /24 or larger) |
| `az_count` | number | 2 | Availability Zones to span (2 or 3) |
| `enable_nat_gateway` | bool | true | NAT for private-subnet egress |
| `single_nat_gateway` | bool | false | One NAT for all AZs (cheaper, not HA) |
| `enable_flow_logs` | bool | true | VPC flow logs to CloudWatch |
| `flow_log_retention_days` | number | 90 | Flow-log retention |
| `tags` | map(string) | {} | Extra tags on every resource |

## Outputs

`vpc_id`, `vpc_cidr_block`, `public_subnet_ids`, `private_subnet_ids`, `nat_gateway_ids`, `flow_log_group`.
