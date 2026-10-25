#!/usr/bin/env python3
"""TLS endpoint audit: certificate validity, expiry, hostname match and protocol support.

    tls_audit.py mail.example.com portal.example.com:8443
    tls_audit.py -f endpoints.txt --warn 30 --crit 7 --format json
    tls_audit.py vpn.example.com --protocols          # also test which TLS versions are accepted

Exit codes follow the Nagios/Icinga convention so it drops straight into monitoring:
0 OK, 1 WARNING (expires within --warn days), 2 CRITICAL (invalid, expired, legacy TLS accepted or
expires within --crit days), 3 UNKNOWN (unreachable).
"""

from __future__ import annotations

import argparse
import json
import socket
import ssl
import sys
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime

OK, WARNING, CRITICAL, UNKNOWN = 0, 1, 2, 3
STATUS = {OK: "OK", WARNING: "WARNING", CRITICAL: "CRITICAL", UNKNOWN: "UNKNOWN"}
LEGACY = ("TLSv1", "TLSv1.1")


@dataclass
class Report:
    target: str
    status: int = UNKNOWN
    verified: bool = False
    verify_error: str = ""
    subject: str = ""
    issuer: str = ""
    sans: list[str] = field(default_factory=list)
    not_after: str = ""
    days_left: int | None = None
    protocol: str = ""
    cipher: str = ""
    accepted_versions: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)


def split_target(text: str) -> tuple[str, int]:
    text = text.strip()
    if text.startswith("["):  # [IPv6]:port
        host, _, rest = text[1:].partition("]")
        return host, int(rest.lstrip(":") or 443)
    host, sep, port = text.rpartition(":")
    if sep and port.isdigit() and ":" not in host:
        return host, int(port)
    return text, 443


SHORT = {"commonName": "CN", "organizationName": "O", "countryName": "C", "organizationalUnitName": "OU"}


def name_of(rdn_seq: tuple) -> str:
    """'CN=..., O=...' from the getpeercert() RDN structure."""
    return ", ".join(f"{SHORT.get(k, k)}={v}" for rdn in rdn_seq for k, v in rdn)


def days_until(not_after: str, now: datetime | None = None) -> int:
    expires = datetime.fromtimestamp(ssl.cert_time_to_seconds(not_after), UTC)
    return (expires - (now or datetime.now(UTC))).days


def fetch(host: str, port: int, timeout: float, verify: bool) -> tuple[dict, str, str]:
    ctx = ssl.create_default_context()
    if not verify:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection((host, port), timeout=timeout) as raw, \
            ctx.wrap_socket(raw, server_hostname=host) as tls:
        cert = tls.getpeercert() if verify else {}
        return cert, tls.version() or "", (tls.cipher() or ("",))[0]


def accepted(host: str, port: int, timeout: float) -> list[str]:
    versions = [("TLSv1", ssl.TLSVersion.TLSv1), ("TLSv1.1", ssl.TLSVersion.TLSv1_1),
                ("TLSv1.2", ssl.TLSVersion.TLSv1_2), ("TLSv1.3", ssl.TLSVersion.TLSv1_3)]
    ok = []
    for name, ver in versions:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        try:
            ctx.minimum_version = ctx.maximum_version = ver
            if name in LEGACY:
                ctx.set_ciphers("ALL:@SECLEVEL=0")
            with socket.create_connection((host, port), timeout=timeout) as raw, \
                    ctx.wrap_socket(raw, server_hostname=host):
                ok.append(name)
        except (ssl.SSLError, OSError, ValueError):
            continue
    return ok


def audit(target: str, warn: int, crit: int, timeout: float, protocols: bool) -> Report:
    host, port = split_target(target)
    rep = Report(target=f"{host}:{port}")
    try:
        cert, rep.protocol, rep.cipher = fetch(host, port, timeout, verify=True)
        rep.verified = True
    except ssl.SSLCertVerificationError as exc:
        rep.verify_error = exc.verify_message or str(exc)
        rep.problems.append(f"certificate not trusted: {rep.verify_error}")
        try:
            _, rep.protocol, rep.cipher = fetch(host, port, timeout, verify=False)
        except OSError as exc2:
            rep.problems.append(f"handshake failed: {exc2}")
        cert = {}
    except (OSError, ssl.SSLError) as exc:
        rep.problems.append(f"unreachable: {exc}")
        return rep
    if cert:
        rep.subject = name_of(cert.get("subject", ()))
        rep.issuer = name_of(cert.get("issuer", ()))
        rep.sans = [v for k, v in cert.get("subjectAltName", ()) if k in ("DNS", "IP Address")]
        rep.not_after = cert.get("notAfter", "")
        if rep.not_after:
            rep.days_left = days_until(rep.not_after)
    if protocols:
        rep.accepted_versions = accepted(host, port, timeout)
        legacy = [v for v in rep.accepted_versions if v in LEGACY]
        if legacy:
            rep.problems.append(f"legacy protocol accepted: {', '.join(legacy)}")
    rep.status = classify(rep, warn, crit)
    return rep


def classify(rep: Report, warn: int, crit: int) -> int:
    if not rep.verified or any(p.startswith("legacy") for p in rep.problems):
        return CRITICAL
    if rep.days_left is None:
        return UNKNOWN
    if rep.days_left < max(crit, 0):
        rep.problems.append(f"expires in {rep.days_left} day(s)" if rep.days_left >= 0 else "expired")
        return CRITICAL
    if rep.days_left < warn:
        rep.problems.append(f"expires in {rep.days_left} day(s)")
        return WARNING
    return OK


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("targets", nargs="*", help="host[:port] (default port 443)")
    ap.add_argument("-f", "--file", help="file with one host[:port] per line (# comments allowed)")
    ap.add_argument("--warn", type=int, default=30, help="warning threshold in days (default 30)")
    ap.add_argument("--crit", type=int, default=14, help="critical threshold in days (default 14)")
    ap.add_argument("--timeout", type=float, default=5.0)
    ap.add_argument("--protocols", action="store_true", help="test TLS 1.0-1.3 acceptance (flags 1.0/1.1)")
    ap.add_argument("--format", choices=["table", "json"], default="table")
    args = ap.parse_args(argv)
    targets = list(args.targets)
    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            targets += [line.split("#")[0].strip() for line in fh if line.split("#")[0].strip()]
    if not targets:
        ap.error("give at least one target or --file")
    reports = [audit(t, args.warn, args.crit, args.timeout, args.protocols) for t in targets]
    worst = max(r.status for r in reports)
    if args.format == "json":
        print(json.dumps([asdict(r) for r in reports], indent=2))
    else:
        for r in reports:
            days = "-" if r.days_left is None else str(r.days_left)
            print(f"{STATUS[r.status]:<9} {r.target:<40} {days:>5}d  {r.protocol:<8} {r.issuer[:40]}")
            for p in r.problems:
                print(f"{'':10}- {p}")
            if r.accepted_versions:
                print(f"{'':10}  accepts: {', '.join(r.accepted_versions)}")
        print(f"\n{STATUS[worst]}: {len(reports)} endpoint(s) checked")
    return worst


if __name__ == "__main__":
    sys.exit(main())
