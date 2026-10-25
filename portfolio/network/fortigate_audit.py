#!/usr/bin/env python3
"""FortiGate configuration audit: risky firewall policies, shadowed rules and exposed management.

Reads a FortiOS configuration backup (System > Configuration > Backup, or `show full-configuration` output) and
reports, with severities and remediation:

  * accept policies that allow any source to any destination on any service
  * inbound policies from WAN interfaces with unrestricted destinations or services
  * accept policies without logging, and internet-bound policies without security profiles
  * shadowed policies that can never match (an earlier policy covers them), including address/service groups
  * administrative access (HTTPS/SSH/HTTP/Telnet/SNMP) enabled on WAN interfaces
  * administrators without trusted hosts, FortiCloud SSO admin login, weak global crypto, SSL-VPN on WAN

    fortigate_audit.py FGT60F_backup.conf
    fortigate_audit.py backup.conf --wan wan1,wan2 --format markdown > fortigate-audit.md
    fortigate_audit.py backup.conf --format json --fail-on high      # CI / scheduled check

VDOM configurations are supported (policies are reported per VDOM).
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from dataclasses import asdict, dataclass, field

SEVERITY = ["info", "low", "medium", "high", "critical"]
ADMIN_PROTOCOLS = {"https", "ssh", "http", "telnet", "snmp", "fgfm", "radius-acct", "ftm"}


# ---------------------------------------------------------------- parser
@dataclass
class Node:
    settings: dict[str, list[str]] = field(default_factory=dict)
    blocks: dict[str, Block] = field(default_factory=dict)

    def get(self, key: str, default: str = "") -> str:
        values = self.settings.get(key)
        return values[0] if values else default

    def values(self, key: str) -> list[str]:
        return self.settings.get(key, [])


@dataclass
class Block(Node):
    entries: dict[str, Node] = field(default_factory=dict)


def _balanced(text: str) -> bool:
    return len(re.findall(r'(?<!\\)"', text)) % 2 == 0


def parse_config(text: str) -> tuple[Node, dict[str, str]]:
    """Parse FortiOS CLI configuration into nested blocks; also returns header metadata (model, version)."""
    root = Node()
    stack: list[Node] = [root]
    meta: dict[str, str] = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if line.startswith("#config-version="):
            parts = line.split("=", 1)[1].split("-")
            meta = {"model": parts[0], "version": parts[1] if len(parts) > 1 else "",
                    "build": next((p for p in parts if p.startswith("build")), "")}
            continue
        if not line or line.startswith("#"):
            continue
        while not _balanced(line) and i < len(lines):  # quoted values (certificates, comments) span lines
            line += "\n" + lines[i]
            i += 1
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        if not words:
            continue
        keyword, args = words[0], words[1:]
        top = stack[-1]
        if keyword == "config":
            block = top.blocks.setdefault(" ".join(args), Block())
            stack.append(block)
        elif keyword == "edit" and isinstance(top, Block):
            stack.append(top.entries.setdefault(args[0] if args else "", Node()))
        elif keyword == "set" and args:
            top.settings[args[0]] = args[1:]
        elif keyword == "unset" and args:
            top.settings.pop(args[0], None)
        elif keyword in ("next", "end") and len(stack) > 1:
            stack.pop()
    return root, meta


def find_blocks(node: Node, name: str, vdom: str = "root") -> list[tuple[str, Block]]:
    """Every block with this name, labelled with its VDOM (searches inside `config vdom` entries)."""
    found = [(vdom, node.blocks[name])] if name in node.blocks else []
    vdoms = node.blocks.get("vdom")
    if vdoms:
        for vname, entry in vdoms.entries.items():
            found += find_blocks(entry, name, vname)
    glob = node.blocks.get("global")
    if glob and name in glob.blocks:
        found.append(("global", glob.blocks[name]))
    return found


# ---------------------------------------------------------------- analysis
@dataclass
class Finding:
    id: str
    severity: str
    scope: str
    object: str
    message: str
    remediation: str


@dataclass
class Policy:
    pid: str
    name: str
    node: Node
    index: int

    def set_of(self, key: str) -> set[str]:
        return set(self.node.values(key))

    @property
    def enabled(self) -> bool:
        return self.node.get("status", "enable") != "disable"

    @property
    def action(self) -> str:
        return self.node.get("action", "deny")

    @property
    def label(self) -> str:
        return f"policy {self.pid}" + (f' "{self.name}"' if self.name else "")


class Expander:
    """Resolves address and service groups to member sets (recursively)."""

    def __init__(self, root: Node, vdom_node: Node) -> None:
        self.groups: dict[str, set[str]] = {}
        for container in (root, vdom_node):
            for block_name in ("firewall addrgrp", "firewall service group", "firewall addrgrp6"):
                block = container.blocks.get(block_name)
                if block:
                    for gname, entry in block.entries.items():
                        self.groups[gname] = set(entry.values("member"))

    def expand(self, names: set[str], depth: int = 0) -> set[str]:
        out: set[str] = set()
        for name in names:
            if name in self.groups and depth < 16:
                out |= self.expand(self.groups[name], depth + 1)
            else:
                out.add(name)
        return out


def covers(outer: set[str], inner: set[str], wildcard: str) -> bool:
    return wildcard in outer or (bool(inner) and inner <= outer)


def wan_interfaces(root: Node, extra: list[str]) -> set[str]:
    wans = set(extra)
    for _, block in find_blocks(root, "system interface"):
        for name, entry in block.entries.items():
            if entry.get("role") == "wan" or re.fullmatch(r"wan\d*", name):
                wans.add(name)
    return wans


def audit_policies(root: Node, wans: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    vdom_nodes = {"root": root}
    if "vdom" in root.blocks:
        vdom_nodes.update(root.blocks["vdom"].entries)
    for vdom, block in find_blocks(root, "firewall policy"):
        exp = Expander(root, vdom_nodes.get(vdom, root))
        policies = [Policy(pid, e.get("name"), e, i) for i, (pid, e) in enumerate(block.entries.items())]
        for p in policies:
            src_wan = bool(p.set_of("srcintf") & wans)
            dst_wan = bool(p.set_of("dstintf") & wans)
            any_src = "all" in p.set_of("srcaddr")
            any_dst = "all" in p.set_of("dstaddr") and p.node.get("internet-service") != "enable"
            any_svc = "ALL" in p.set_of("service")
            if not p.enabled:
                findings.append(Finding("FGT-POL-010", "low", vdom, p.label, "policy is disabled",
                                        "delete unused policies so the rule base reflects intent"))
                continue
            if p.action != "accept":
                continue
            if any_src and any_dst and any_svc:
                sev = "critical" if src_wan else "high"
                findings.append(Finding("FGT-POL-001", sev, vdom, p.label,
                                        f"accepts any source to any destination on ALL services "
                                        f"({'/'.join(p.node.values('srcintf'))} -> "
                                        f"{'/'.join(p.node.values('dstintf'))})",
                                        "restrict source, destination and service to what is required"))
            elif src_wan and (any_dst or any_svc):
                findings.append(Finding("FGT-POL-002", "high", vdom, p.label,
                                        "inbound from a WAN interface with an unrestricted "
                                        + ("destination" if any_dst else "service"),
                                        "publish specific services through VIPs and restrict sources"))
            if p.node.get("logtraffic", "utm") == "disable":
                findings.append(Finding("FGT-POL-003", "medium", vdom, p.label, "accept policy does not log traffic",
                                        "set logtraffic all (or utm) for accountability and incident response"))
            if dst_wan and not src_wan:
                profiles = [k for k in ("av-profile", "webfilter-profile", "ips-sensor", "application-list",
                                        "dnsfilter-profile") if p.node.get(k)]
                utm = p.node.get("utm-status") == "enable" or p.node.get("profile-type") == "group"
                if not utm or not profiles:
                    findings.append(Finding("FGT-POL-004", "medium", vdom, p.label,
                                            "internet-bound policy without security profiles (AV/IPS/web/app)",
                                            "enable utm-status with at least IPS, application control and "
                                            "web/DNS filtering"))
            if "enable" in (p.node.get("srcaddr-negate"), p.node.get("dstaddr-negate"),
                            p.node.get("service-negate")):
                findings.append(Finding("FGT-POL-005", "info", vdom, p.label, "uses address/service negation",
                                        "review negated rules carefully; they match more than they appear to"))
        findings += shadowed(policies, exp, vdom)
    return findings


def shadowed(policies: list[Policy], exp: Expander, vdom: str) -> list[Finding]:
    out = []
    active = [p for p in policies if p.enabled]
    for i, later in enumerate(active):
        if any(later.node.get(k) == "enable" for k in ("srcaddr-negate", "dstaddr-negate", "service-negate",
                                                         "internet-service")):
            continue
        for earlier in active[:i]:
            if any(earlier.node.get(k) == "enable" for k in ("srcaddr-negate", "dstaddr-negate",
                                                               "service-negate", "internet-service")):
                continue
            identity = ("groups", "users")
            if any(earlier.set_of(k) for k in identity) and any(earlier.set_of(k) != later.set_of(k) for k in identity):
                continue
            if earlier.node.get("schedule", "always") not in ("always", later.node.get("schedule", "always")):
                continue
            if (covers(earlier.set_of("srcintf"), later.set_of("srcintf"), "any")
                    and covers(earlier.set_of("dstintf"), later.set_of("dstintf"), "any")
                    and covers(exp.expand(earlier.set_of("srcaddr")), exp.expand(later.set_of("srcaddr")), "all")
                    and covers(exp.expand(earlier.set_of("dstaddr")), exp.expand(later.set_of("dstaddr")), "all")
                    and covers(exp.expand(earlier.set_of("service")), exp.expand(later.set_of("service")), "ALL")):
                conflict = earlier.action == "accept" and later.action != "accept"
                out.append(Finding("FGT-POL-020", "high" if conflict else "medium", vdom, later.label,
                                   f"can never match: {earlier.label} above it covers the same traffic"
                                   + (" and ACCEPTS what this policy was meant to deny" if conflict else ""),
                                   "move the more specific policy above the broader one, or delete it"))
                break
    return out


def audit_system(root: Node, wans: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    for scope, block in find_blocks(root, "system interface"):
        for name, entry in block.entries.items():
            access = set(entry.values("allowaccess"))
            exposed = sorted(access & ADMIN_PROTOCOLS)
            if name in wans and exposed:
                findings.append(Finding("FGT-SYS-001", "high", scope, f"interface {name}",
                                        f"administrative access on a WAN interface: {', '.join(exposed)}",
                                        "remove admin protocols from WAN; manage over VPN or a management VLAN"))
            plain = sorted(access & {"http", "telnet"})
            if plain:
                findings.append(Finding("FGT-SYS-002", "medium", scope, f"interface {name}",
                                        f"cleartext admin protocol enabled: {', '.join(plain)}",
                                        "use HTTPS and SSH only"))
    for scope, block in find_blocks(root, "system global"):
        if block.get("admin-forticloud-sso-login") == "enable":
            findings.append(Finding("FGT-SYS-010", "high", scope, "system global",
                                    "FortiCloud SSO administrator login is enabled",
                                    "set admin-forticloud-sso-login disable unless it is required, and patch "
                                    "FortiOS (FortiCloud SSO authentication bypass advisories, e.g. CVE-2025-59718)"))
        if block.get("strong-crypto") == "disable":
            findings.append(Finding("FGT-SYS-011", "medium", scope, "system global", "strong-crypto is disabled",
                                    "set strong-crypto enable (disables weak ciphers for admin and VPN)"))
        timeout = block.get("admintimeout")
        if timeout.isdigit() and int(timeout) > 15:
            findings.append(Finding("FGT-SYS-012", "low", scope, "system global",
                                    f"admin idle timeout is {timeout} minutes", "set admintimeout 15 or lower"))
    for scope, block in find_blocks(root, "system admin"):
        for name, entry in block.entries.items():
            trusted = [k for k in entry.settings if re.fullmatch(r"trusthost\d+", k)
                       and entry.get(k) not in ("0.0.0.0", "")]
            if not trusted:
                findings.append(Finding("FGT-SYS-020", "medium", scope, f"admin {name}",
                                        "administrator can log in from any address (no trusted hosts)",
                                        "set trusthost1..n to the management networks"))
            if name == "admin":
                findings.append(Finding("FGT-SYS-021", "low", scope, "admin admin",
                                        "the default 'admin' account exists",
                                        "create named super_admin accounts, then rename or remove 'admin'"))
    for scope, block in find_blocks(root, "vpn ssl settings"):
        src = set(block.values("source-interface"))
        if block.get("status", "enable") != "disable" and src & wans:
            findings.append(Finding("FGT-VPN-001", "medium", scope, "vpn ssl settings",
                                    f"SSL-VPN listens on WAN ({', '.join(sorted(src & wans))})",
                                    "prefer IPsec or ZTNA; otherwise restrict source addresses and keep "
                                    "FortiOS patched (SSL-VPN has a history of critical vulnerabilities)"))
    return findings


def render(findings: list[Finding], meta: dict[str, str], fmt: str, source: str) -> str:
    findings = sorted(findings, key=lambda f: (-SEVERITY.index(f.severity), f.scope, f.id))
    if fmt == "json":
        return json.dumps({"source": source, "device": meta, "findings": [asdict(f) for f in findings]}, indent=2)
    counts = {s: sum(f.severity == s for f in findings) for s in reversed(SEVERITY)}
    head = f"{source}: {meta.get('model', '?')} FortiOS {meta.get('version', '?')} {meta.get('build', '')}".strip()
    summary = ", ".join(f"{n} {s}" for s, n in counts.items() if n) or "no findings"
    if fmt == "markdown":
        lines = [f"# FortiGate audit: {head}", "", f"**{summary}**", "",
                 "| Severity | ID | VDOM | Object | Finding | Remediation |", "|---|---|---|---|---|---|"]
        lines += [f"| {f.severity} | {f.id} | {f.scope} | {f.object} | {f.message} | {f.remediation} |"
                  for f in findings]
        return "\n".join(lines)
    lines = [head, summary, ""]
    for f in findings:
        lines.append(f"[{f.severity.upper():<8}] {f.id}  {f.scope}/{f.object}: {f.message}")
        lines.append(f"{'':12}fix: {f.remediation}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("config", help="FortiOS configuration backup file")
    ap.add_argument("--wan", default="", help="extra WAN interface names, comma-separated")
    ap.add_argument("--format", choices=["table", "markdown", "json"], default="table")
    ap.add_argument("--fail-on", choices=SEVERITY, default="critical", help="exit 2 at or above this severity")
    args = ap.parse_args(argv)
    with open(args.config, encoding="utf-8", errors="replace") as fh:
        root, meta = parse_config(fh.read())
    wans = wan_interfaces(root, [w.strip() for w in args.wan.split(",") if w.strip()])
    findings = audit_policies(root, wans) + audit_system(root, wans)
    print(render(findings, meta, args.format, args.config))
    threshold = SEVERITY.index(args.fail_on)
    return 2 if any(SEVERITY.index(f.severity) >= threshold for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
