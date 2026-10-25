#!/usr/bin/env python3
"""Cisco IOS / IOS-XE hardening audit of running-configs (one file or a directory of backups).

Checks management-plane hardening in the spirit of the CIS Cisco IOS benchmark: password storage, AAA,
SSH vs Telnet on VTY lines, VTY access-classes and timeouts, SNMP communities, HTTP server, logging, NTP,
timestamps, source routing, banners and risky interface settings. Each finding carries a remediation command.

    cisco_ios_audit.py core-sw01.cfg
    cisco_ios_audit.py backups/ --format markdown > ios-audit.md
    cisco_ios_audit.py backups/ --format json --fail-on high
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

SEVERITY = ["info", "low", "medium", "high", "critical"]
WEIGHT = {"info": 0, "low": 1, "medium": 3, "high": 7, "critical": 10}


@dataclass
class Finding:
    device: str
    id: str
    severity: str
    message: str
    fix: str


class Config:
    """IOS config as (line, children) sections, based on indentation."""

    def __init__(self, text: str) -> None:
        self.lines = [ln.rstrip() for ln in text.splitlines() if ln.strip() and not ln.startswith("!")]
        self.sections: list[tuple[str, list[str]]] = []
        for ln in self.lines:
            if ln.startswith(" ") and self.sections:
                self.sections[-1][1].append(ln.strip())
            elif not ln.startswith(" "):
                self.sections.append((ln.strip(), []))

    def has(self, pattern: str) -> bool:
        return any(re.search(pattern, head) for head, _ in self.sections)

    def find(self, pattern: str) -> list[tuple[str, list[str]]]:
        return [(h, c) for h, c in self.sections if re.search(pattern, h)]

    @property
    def hostname(self) -> str:
        found = self.find(r"^hostname\s+")
        return found[0][0].split()[1] if found else ""


def audit(name: str, text: str) -> list[Finding]:
    cfg = Config(text)
    device = cfg.hostname or name
    out: list[Finding] = []

    def add(fid: str, sev: str, msg: str, fix: str) -> None:
        out.append(Finding(device, fid, sev, msg, fix))

    # ---- credentials
    if cfg.has(r"^enable password\b"):
        add("IOS-001", "high", "'enable password' is set (reversible or plaintext)",
            "no enable password; enable algorithm-type scrypt secret <secret>")
    if not cfg.has(r"^enable (algorithm-type \S+ )?secret\b"):
        add("IOS-002", "high", "no enable secret configured", "enable algorithm-type scrypt secret <secret>")
    elif cfg.has(r"^enable secret 5 "):
        add("IOS-003", "medium", "enable secret uses type 5 (MD5)", "enable algorithm-type scrypt secret <secret>")
    for head, _ in cfg.find(r"^username \S+ .*\bpassword\b"):
        add("IOS-004", "high", f"local user '{head.split()[1]}' uses 'password' (type 0/7, reversible)",
            f"username {head.split()[1]} algorithm-type scrypt secret <secret>")
    for head, _ in cfg.find(r"^username \S+ .*\bsecret 5 "):
        add("IOS-005", "medium", f"local user '{head.split()[1]}' secret is type 5 (MD5)",
            f"username {head.split()[1]} algorithm-type scrypt secret <secret>")
    if not cfg.has(r"^service password-encryption"):
        add("IOS-006", "low", "service password-encryption is off (type 7 obfuscation for legacy lines)",
            "service password-encryption")
    # ---- AAA
    if not cfg.has(r"^aaa new-model"):
        add("IOS-010", "medium", "AAA is not enabled", "aaa new-model; aaa authentication login default group "
            "<radius|tacacs+> local")
    # ---- VTY / console lines
    for head, children in cfg.find(r"^line vty"):
        transport = next((c for c in children if c.startswith("transport input")), "")
        if re.search(r"\b(telnet|all)\b", transport):
            add("IOS-020", "high", f"{head}: Telnet allowed ({transport})", f"{head} / transport input ssh")
        elif not transport:
            add("IOS-020", "medium", f"{head}: no explicit 'transport input' (older IOS defaults to all, "
                "including Telnet)", f"{head} / transport input ssh")
        if not any(c.startswith("access-class") for c in children):
            add("IOS-021", "medium", f"{head}: no access-class restricting management sources",
                f"{head} / access-class MGMT-ACL in")
        if any(re.fullmatch(r"exec-timeout 0( 0)?", c) for c in children):
            add("IOS-022", "medium", f"{head}: exec-timeout disabled", f"{head} / exec-timeout 10 0")
        if "no login" in children:
            add("IOS-023", "critical", f"{head}: 'no login' (no authentication)",
                f"{head} / login authentication default")
    for head, children in cfg.find(r"^line con"):
        if any(re.fullmatch(r"exec-timeout 0( 0)?", c) for c in children):
            add("IOS-024", "low", f"{head}: exec-timeout disabled", f"{head} / exec-timeout 10 0")
    if not cfg.has(r"^ip ssh version 2"):
        add("IOS-025", "medium", "SSH version 2 is not enforced", "ip ssh version 2")
    # ---- SNMP
    for head, _ in cfg.find(r"^snmp-server community "):
        parts = head.split()
        community = parts[2]
        if community.lower() in ("public", "private", "cisco", "community"):
            add("IOS-030", "high", f"SNMP community '{community}' is a well-known default",
                f"no snmp-server community {community}; use SNMPv3 (snmp-server group ... v3 priv)")
        if "RW" in parts:
            add("IOS-031", "high", f"SNMP community '{community}' has write access (RW)",
                f"snmp-server community <new> RO <acl>; no snmp-server community {community}")
        if len(parts) <= 4 and not re.search(r"\b(RO|RW)\s+\S+$", head):
            add("IOS-032", "medium", f"SNMP community '{community}' has no ACL",
                f"snmp-server community {community} RO SNMP-ACL")
    # ---- services
    if cfg.has(r"^ip http server"):
        add("IOS-040", "medium", "HTTP server enabled (cleartext web management)", "no ip http server")
    if not cfg.has(r"^no ip source-route"):
        add("IOS-041", "low", "IP source routing not disabled", "no ip source-route")
    if cfg.has(r"^service pad"):
        add("IOS-042", "low", "PAD service enabled", "no service pad")
    if cfg.has(r"^ip finger|^service finger"):
        add("IOS-043", "low", "finger service enabled", "no ip finger")
    if cfg.has(r"^ip bootp server"):
        add("IOS-044", "low", "BOOTP server enabled", "no ip bootp server")
    if not cfg.has(r"^no cdp run") and not cfg.has(r"^no lldp run"):
        add("IOS-045", "info", "CDP/LLDP run globally; disable on untrusted/edge ports", "interface X / no cdp enable")
    # ---- logging / time
    if not cfg.has(r"^logging (host )?\d+\.\d+\.\d+\.\d+|^logging host "):
        add("IOS-050", "low", "no remote syslog server", "logging host <syslog-ip>; logging trap informational")
    if not cfg.has(r"^service timestamps log datetime"):
        add("IOS-051", "low", "log timestamps lack date/time",
            "service timestamps log datetime msec localtime show-timezone")
    if not cfg.has(r"^ntp server "):
        add("IOS-052", "low", "no NTP server", "ntp server <ntp-ip> prefer")
    if not cfg.has(r"^logging buffered"):
        add("IOS-053", "info", "no local log buffer", "logging buffered 64000 informational")
    if not cfg.has(r"^login block-for "):
        add("IOS-054", "low", "no login brute-force protection", "login block-for 120 attempts 5 within 60")
    if not cfg.has(r"^banner (login|motd)"):
        add("IOS-055", "low", "no legal login banner", "banner login ^ Authorized access only ^")
    # ---- interfaces
    for head, children in cfg.find(r"^interface "):
        if "shutdown" in children:
            continue
        if "ip directed-broadcast" in children:
            add("IOS-060", "medium", f"{head}: ip directed-broadcast enabled", f"{head} / no ip directed-broadcast")
        has_ip = any(c.startswith("ip address") and "no ip address" not in c for c in children)
        if has_ip and "no ip proxy-arp" not in children:
            add("IOS-061", "info", f"{head}: proxy ARP enabled (default)", f"{head} / no ip proxy-arp")
        if "switchport mode access" in children and not any(c.startswith("spanning-tree bpduguard enable")
                                                              or c == "spanning-tree portfast" for c in children):
            add("IOS-062", "info", f"{head}: access port without portfast/BPDU guard",
                f"{head} / spanning-tree portfast; spanning-tree bpduguard enable")
    return out


def score(findings: list[Finding]) -> int:
    return max(0, 100 - sum(WEIGHT[f.severity] for f in findings))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="+", help="config files or directories (*.cfg, *.txt, *.conf)")
    ap.add_argument("--format", choices=["table", "markdown", "json"], default="table")
    ap.add_argument("--fail-on", choices=SEVERITY, default="critical")
    args = ap.parse_args(argv)
    files: list[Path] = []
    for p in map(Path, args.paths):
        files += sorted(f for f in p.iterdir() if f.suffix in (".cfg", ".txt", ".conf")) if p.is_dir() else [p]
    texts = {f.name: f.read_text(encoding="utf-8", errors="replace") for f in files}
    # In a directory, skip files that are not IOS configs (no hostname/version/interface lines).
    texts = {n: t for n, t in texts.items()
             if len(files) == 1 or re.search(r"^(hostname|version|interface) ", t, re.M)}
    results = {Config(t).hostname or Path(n).stem: audit(Path(n).stem, t) for n, t in texts.items()}
    every = [x for fs in results.values() for x in fs]
    if args.format == "json":
        print(json.dumps({name: {"score": score(fs), "findings": [asdict(x) for x in fs]}
                          for name, fs in results.items()}, indent=2))
    elif args.format == "markdown":
        print("# Cisco IOS hardening audit\n")
        print("| Device | Score | Critical | High | Medium | Low |\n|---|---|---|---|---|---|")
        for name, fs in results.items():
            c = {s: sum(x.severity == s for x in fs) for s in SEVERITY}
            print(f"| {name} | {score(fs)} | {c['critical']} | {c['high']} | {c['medium']} | {c['low']} |")
        print("\n| Device | Severity | ID | Finding | Fix |\n|---|---|---|---|---|")
        for x in sorted(every, key=lambda x: (x.device, -SEVERITY.index(x.severity))):
            print(f"| {x.device} | {x.severity} | {x.id} | {x.message} | `{x.fix}` |")
    else:
        for name, fs in results.items():
            print(f"== {name}  score {score(fs)}/100")
            for x in sorted(fs, key=lambda x: -SEVERITY.index(x.severity)):
                print(f"  [{x.severity.upper():<8}] {x.id} {x.message}\n{'':14}fix: {x.fix}")
    threshold = SEVERITY.index(args.fail_on)
    return 2 if any(SEVERITY.index(x.severity) >= threshold for x in every) else 0


if __name__ == "__main__":
    sys.exit(main())
