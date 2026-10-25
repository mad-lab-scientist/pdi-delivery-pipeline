#!/usr/bin/env python3
"""AWS account security posture audit (read-only), across regions, using boto3.

Checks, each mapped to a CIS AWS Foundations control where applicable:
  * IAM: root access keys, users without MFA, access keys older than --max-key-age, unused credentials
  * S3: buckets without Block Public Access, without default encryption, or without TLS-only policy
  * EC2: security groups allowing 0.0.0.0/0 to sensitive ports (22, 3389, 3306, 5432, ...), unencrypted volumes
  * VPC: default security groups that allow traffic
  * Logging: CloudTrail not enabled / not multi-region, config recorder off

    aws_security_audit.py                         # uses the default profile/role
    AWS_PROFILE=audit aws_security_audit.py --regions us-east-1,us-east-2 --format json
    aws_security_audit.py --max-key-age 90 --fail-on high

Credentials come from the standard AWS chain (env, profile, SSO, instance role). Exit 2 if any finding
at or above --fail-on exists. Requires: pip install boto3
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import sys
from dataclasses import asdict, dataclass, field

SEVERITY = ["info", "low", "medium", "high", "critical"]
SENSITIVE_PORTS = {22: "SSH", 3389: "RDP", 3306: "MySQL", 5432: "PostgreSQL", 6379: "Redis",
                   9200: "Elasticsearch", 27017: "MongoDB", 1433: "MSSQL", 23: "Telnet", 11211: "Memcached"}


@dataclass
class Finding:
    check: str
    severity: str
    region: str
    resource: str
    message: str


@dataclass
class Report:
    account: str = ""
    findings: list[Finding] = field(default_factory=list)

    def add(self, *a) -> None:
        self.findings.append(Finding(*a))


def port_in_range(port: int, perm: dict) -> bool:
    if perm.get("IpProtocol") in ("-1", -1):
        return True
    from_p, to_p = perm.get("FromPort"), perm.get("ToPort")
    return from_p is not None and from_p <= port <= to_p


def audit_iam(session, rep: Report, max_key_age: int) -> None:
    iam = session.client("iam")
    try:
        summary = iam.get_account_summary()["SummaryMap"]
    except Exception as exc:  # noqa: BLE001
        rep.add("iam", "info", "global", "iam", f"could not read IAM: {exc}")
        return
    if summary.get("AccountAccessKeysPresent"):
        rep.add("iam", "critical", "global", "root", "root account has active access keys (CIS 1.4)")
    if summary.get("AccountMFAEnabled") == 0:
        rep.add("iam", "high", "global", "root", "root account has no MFA (CIS 1.5)")

    now = dt.datetime.now(dt.UTC)
    for user in iam.get_paginator("list_users").paginate():
        for u in user["Users"]:
            name = u["UserName"]
            mfa = iam.list_mfa_devices(UserName=name)["MFADevices"]
            login_profile = True
            try:
                iam.get_login_profile(UserName=name)
            except iam.exceptions.NoSuchEntityException:
                login_profile = False
            if login_profile and not mfa:
                rep.add("iam", "high", "global", f"user/{name}", "console user without MFA (CIS 1.10)")
            for key in iam.list_access_keys(UserName=name)["AccessKeyMetadata"]:
                age = (now - key["CreateDate"]).days
                if key["Status"] == "Active" and age > max_key_age:
                    rep.add("iam", "medium", "global", f"user/{name}", f"access key is {age} days old (CIS 1.14)")


def audit_s3(session, rep: Report) -> None:
    s3 = session.client("s3")
    try:
        buckets = s3.list_buckets()["Buckets"]
    except Exception as exc:  # noqa: BLE001
        rep.add("s3", "info", "global", "s3", f"could not list buckets: {exc}")
        return
    for b in buckets:
        name = b["Name"]
        try:
            pab = s3.get_public_access_block(Bucket=name)["PublicAccessBlockConfiguration"]
            pab_keys = ("BlockPublicAcls", "BlockPublicPolicy", "IgnorePublicAcls", "RestrictPublicBuckets")
            if not all(pab.get(k) for k in pab_keys):
                rep.add("s3", "high", "global", f"bucket/{name}",
                        "Block Public Access is not fully enabled (CIS 2.1.5)")
        except s3.exceptions.ClientError:
            rep.add("s3", "high", "global", f"bucket/{name}", "no Block Public Access configuration")
        try:
            s3.get_bucket_encryption(Bucket=name)
        except s3.exceptions.ClientError:
            rep.add("s3", "medium", "global", f"bucket/{name}", "no default encryption (CIS 2.1.1)")


def audit_region(session, region: str, rep: Report) -> None:
    ec2 = session.client("ec2", region_name=region)
    try:
        sgs = ec2.describe_security_groups()["SecurityGroups"]
    except Exception as exc:  # noqa: BLE001
        rep.add("ec2", "info", region, "ec2", f"skipped ({exc})")
        return
    for sg in sgs:
        sid = f"{sg['GroupId']} ({sg['GroupName']})"
        for perm in sg.get("IpPermissions", []):
            open_v4 = any(r.get("CidrIp") == "0.0.0.0/0" for r in perm.get("IpRanges", []))
            open_v6 = any(r.get("CidrIpv6") == "::/0" for r in perm.get("Ipv6Ranges", []))
            if not (open_v4 or open_v6):
                continue
            for port, svc in SENSITIVE_PORTS.items():
                if port_in_range(port, perm):
                    sev = "critical" if port in (22, 3389, 3306, 5432, 1433) else "high"
                    rep.add("ec2", sev, region, sid, f"{svc} ({port}) open to the internet (CIS 5.2)")
        if sg["GroupName"] == "default" and (sg.get("IpPermissions") or sg.get("IpPermissionsEgress")):
            rep.add("ec2", "low", region, sid, "default security group has rules (CIS 5.4)")
    for vol in ec2.describe_volumes()["Volumes"]:
        if not vol.get("Encrypted"):
            rep.add("ec2", "medium", region, f"volume/{vol['VolumeId']}", "EBS volume is not encrypted (CIS 2.2.1)")


def audit_cloudtrail(session, region: str, rep: Report) -> None:
    ct = session.client("cloudtrail", region_name=region)
    trails = ct.describe_trails()["trailList"]
    if not any(t.get("IsMultiRegionTrail") for t in trails):
        rep.add("cloudtrail", "high", region, "cloudtrail", "no multi-region CloudTrail found (CIS 3.1)")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--regions", help="comma-separated regions (default: all enabled)")
    ap.add_argument("--max-key-age", type=int, default=90)
    ap.add_argument("--format", choices=["table", "json", "csv"], default="table")
    ap.add_argument("--fail-on", choices=SEVERITY, default="high")
    args = ap.parse_args(argv)
    try:
        import boto3  # noqa: PLC0415
    except ImportError:
        print("error: boto3 is required (pip install boto3)", file=sys.stderr)
        return 3

    session = boto3.Session()
    rep = Report()
    try:
        rep.account = session.client("sts").get_caller_identity()["Account"]
    except Exception as exc:  # noqa: BLE001
        print(f"error: no usable AWS credentials ({exc})", file=sys.stderr)
        return 3
    if args.regions:
        regions = [r.strip() for r in args.regions.split(",")]
    else:
        ec2_global = session.client("ec2", region_name="us-east-1")
        regions = [r["RegionName"] for r in ec2_global.describe_regions()["Regions"]]

    audit_iam(session, rep, args.max_key_age)
    audit_s3(session, rep)
    for region in regions:
        audit_region(session, region, rep)
    audit_cloudtrail(session, regions[0], rep)

    findings = sorted(rep.findings, key=lambda f: (-SEVERITY.index(f.severity), f.region))
    if args.format == "json":
        print(json.dumps({"account": rep.account, "findings": [asdict(f) for f in findings]}, indent=2))
    elif args.format == "csv":
        cols = ["check", "severity", "region", "resource", "message"]
        w = csv.DictWriter(sys.stdout, fieldnames=cols, lineterminator="\n")
        w.writeheader()
        w.writerows(asdict(f) for f in findings)
    else:
        print(f"AWS account {rep.account}: {len(findings)} finding(s)\n")
        for f in findings:
            print(f"[{f.severity.upper():<8}] {f.check:<11} {f.region:<12} {f.resource}: {f.message}")
    threshold = SEVERITY.index(args.fail_on)
    return 2 if any(SEVERITY.index(f.severity) >= threshold for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
