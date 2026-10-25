#!/usr/bin/env python3
"""Turn nmap XML output into a readable service inventory and a notable-exposure summary.

Pure parsing of nmap's -oX / -oA XML (standard library only); it runs no scans. Pairs with recon.py.

    parse_nmap.py recon-20261025.xml                       # table to the screen
    parse_nmap.py recon-20261025.xml --format markdown > report.md
    parse_nmap.py recon-20261025.xml --format csv > services.csv

Notable exposures flagged: cleartext admin/file protocols (telnet, ftp, rlogin, rsh, vnc), exposed
databases and management services, SMB, SNMP, and RDP. These are observations for the assessor to verify,
not vulnerabilities on their own.
"""

from __future__ import annotations

import argparse
import csv
import sys
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass

NOTABLE = {
    "telnet": ("high", "cleartext remote administration"),
    "ftp": ("medium", "cleartext file transfer"),
    "rlogin": ("high", "legacy cleartext remote login"),
    "rsh": ("high", "legacy cleartext remote shell"),
    "rexec": ("high", "legacy cleartext remote exec"),
    "vnc": ("high", "remote desktop, often weak/no auth"),
    "ms-wbt-server": ("medium", "RDP exposed"),
    "microsoft-ds": ("medium", "SMB exposed"),
    "netbios-ssn": ("medium", "SMB/NetBIOS exposed"),
    "snmp": ("medium", "SNMP exposed (check for public/default community)"),
    "mysql": ("high", "database exposed"),
    "ms-sql-s": ("high", "database exposed"),
    "postgresql": ("high", "database exposed"),
    "mongodb": ("high", "database exposed"),
    "redis": ("high", "data store, often no auth"),
    "memcached": ("high", "often no auth, DDoS amplifier"),
    "elasticsearch": ("high", "search cluster exposed"),
    "ldap": ("low", "directory service exposed"),
    "smtp": ("low", "mail service; check for open relay"),
    "http": ("info", "web service"),
}


@dataclass
class ServiceRow:
    host: str
    hostname: str
    port: int
    protocol: str
    state: str
    service: str
    product: str
    version: str
    severity: str
    note: str


def parse(path: str) -> list[ServiceRow]:
    rows: list[ServiceRow] = []
    root = ET.parse(path).getroot()  # noqa: S314 - local nmap output, not untrusted network input
    for host in root.findall("host"):
        status = host.find("status")
        if status is not None and status.get("state") != "up":
            continue
        addr_el = host.find("address[@addrtype='ipv4']")
        if addr_el is None:
            addr_el = host.find("address")
        addr = addr_el.get("addr") if addr_el is not None else "?"
        hn_el = host.find("hostnames/hostname")
        hostname = hn_el.get("name") if hn_el is not None else ""
        for port in host.findall("ports/port"):
            state = port.find("state")
            if state is None or state.get("state") != "open":
                continue
            svc = port.find("service")
            name = svc.get("name", "") if svc is not None else ""
            product = svc.get("product", "") if svc is not None else ""
            version = svc.get("version", "") if svc is not None else ""
            severity, note = NOTABLE.get(name, ("", ""))
            rows.append(ServiceRow(
                host=addr, hostname=hostname, port=int(port.get("portid")),
                protocol=port.get("protocol"), state="open", service=name,
                product=product, version=version, severity=severity, note=note))
    return rows


def render(rows: list[ServiceRow], fmt: str) -> str:
    rows = sorted(rows, key=lambda r: (r.host, r.port))
    if fmt == "csv":
        out: list[str] = []
        w = csv.DictWriter(_Sink(out), fieldnames=list(asdict(rows[0]).keys()) if rows else ["host"],
                           lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow(asdict(r))
        return "".join(out)
    notable = [r for r in rows if r.severity]
    if fmt == "markdown":
        lines = [f"# Service inventory ({len({r.host for r in rows})} host(s), {len(rows)} open service(s))", ""]
        if notable:
            order = {"high": 0, "medium": 1, "low": 2, "info": 3, "": 4}
            lines += ["## Notable exposures", "", "| Host | Port | Service | Severity | Note |",
                      "|---|---|---|---|---|"]
            for r in sorted(notable, key=lambda r: order.get(r.severity, 9)):
                lines.append(f"| {r.host} | {r.port}/{r.protocol} | {r.service} | {r.severity} | {r.note} |")
            lines.append("")
        lines += ["## All open services", "", "| Host | Hostname | Port | Service | Product | Version |",
                  "|---|---|---|---|---|---|"]
        for r in rows:
            lines.append(f"| {r.host} | {r.hostname} | {r.port}/{r.protocol} | {r.service} | "
                         f"{r.product} | {r.version} |")
        return "\n".join(lines) + "\n"
    # table
    lines = [f"{'HOST':<16} {'PORT':<9} {'SERVICE':<16} {'PRODUCT/VERSION':<30} NOTE"]
    for r in rows:
        pv = f"{r.product} {r.version}".strip()
        flag = f"[{r.severity}] {r.note}" if r.severity else ""
        lines.append(f"{r.host:<16} {str(r.port) + '/' + r.protocol:<9} {r.service:<16} {pv[:30]:<30} {flag}")
    lines.append(f"\n{len({r.host for r in rows})} host(s), {len(rows)} open service(s), "
                 f"{len(notable)} notable exposure(s)")
    return "\n".join(lines)


class _Sink:
    def __init__(self, sink: list[str]) -> None:
        self.sink = sink

    def write(self, text: str) -> None:
        self.sink.append(text)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("xml_file", help="nmap XML output (-oX / -oA)")
    ap.add_argument("--format", choices=["table", "markdown", "csv"], default="table")
    args = ap.parse_args(argv)
    try:
        rows = parse(args.xml_file)
    except (ET.ParseError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(render(rows, args.format))
    return 0


if __name__ == "__main__":
    sys.exit(main())
