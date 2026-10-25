# cloud

Read-only security-posture auditors for the three major clouds. They report; they change nothing.

| Script | What it does |
|---|---|
| `aws/aws_security_audit.py` | AWS account audit (boto3) across regions, mapped to CIS AWS Foundations: root keys/MFA, users without MFA, old access keys, S3 public-access/encryption, security groups open to the internet on sensitive ports, unencrypted EBS, multi-region CloudTrail. |
| `azure/azure-nsg-audit.sh` | NSG rules allowing sensitive ports from the internet, across one or all subscriptions (`az` + `jq`). |
| `gcp/gcp-firewall-audit.sh` | VPC firewall rules allowing sensitive ports from `0.0.0.0/0`, across one or all projects (`gcloud` + `jq`). |

Credentials come from each provider's standard mechanism (AWS chain / `az login` / `gcloud auth`).
Each tool takes `--format json|csv|table` and exits non-zero when exposures are found, so they drop into CI.

```bash
aws/aws_security_audit.py --regions us-east-1,us-east-2 --fail-on high
azure/azure-nsg-audit.sh --all-subscriptions --format json
gcp/gcp-firewall-audit.sh --project my-project
```

For provisioning these clouds as code, see [`../terraform/`](../terraform/).
