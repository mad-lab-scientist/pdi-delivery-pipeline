#!/usr/bin/env python3
"""Engagement scope loader and authorization gate for authorized security assessments.

Every tool in kali/ loads a scope file first and refuses to touch anything that is not explicitly
in scope, inside the authorized time window, and not on the exclusion list. This enforces, in code, the
rules of engagement from a signed Authorization to Test / Statement of Work. Scanning systems you are
not authorized to test is unlawful; this module exists to make staying in scope the default.

Scope file (JSON, or YAML when PyYAML is available), e.g. scope.example.yaml:

    engagement:
      id: PDI-2026-014
      client: Example Corp
      authorized_by: Jane Smith, CISO
      authorization_ref: SOW-2026-014, Authorization to Test signed 2026-10-20
      start: "2026-10-25"
      end:   "2026-11-01"
    scope:
      in_scope:    [192.0.2.0/24, app.example.com]
      out_of_scope: [192.0.2.1]        # excluded even though inside an in-scope range
    constraints:
      max_rate: 500                    # packets/sec ceiling the tools must honor

Use as a library (see recon.py) or check a target from the shell:

    python scope.py scope.yaml --check 192.0.2.50
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import socket
import sys
from dataclasses import dataclass, field
from datetime import date, datetime


class ScopeError(Exception):
    """Raised when the scope file is invalid or an action would fall outside it."""


@dataclass
class Scope:
    engagement: dict
    in_scope: list[str]
    out_of_scope: list[str] = field(default_factory=list)
    constraints: dict = field(default_factory=dict)
    _in_nets: list = field(default_factory=list, repr=False)
    _out_nets: list = field(default_factory=list, repr=False)
    _in_hosts: set[str] = field(default_factory=set, repr=False)
    _out_hosts: set[str] = field(default_factory=set, repr=False)

    @classmethod
    def load(cls, path: str) -> Scope:
        raw = _read_structured(path)
        for key in ("engagement", "scope"):
            if key not in raw:
                raise ScopeError(f"scope file missing required '{key}' section")
        eng = raw["engagement"]
        for key in ("id", "client", "authorized_by", "authorization_ref", "start", "end"):
            if not eng.get(key):
                raise ScopeError(f"engagement.{key} is required (authorization record must be complete)")
        scope = cls(
            engagement=eng,
            in_scope=list(raw["scope"].get("in_scope", [])),
            out_of_scope=list(raw["scope"].get("out_of_scope", [])),
            constraints=raw.get("constraints", {}),
        )
        if not scope.in_scope:
            raise ScopeError("scope.in_scope is empty; nothing is authorized")
        scope._compile()
        return scope

    def _compile(self) -> None:
        for entry, nets, hosts in ((self.in_scope, self._in_nets, self._in_hosts),
                                   (self.out_of_scope, self._out_nets, self._out_hosts)):
            for item in entry:
                try:
                    nets.append(ipaddress.ip_network(item, strict=False))
                except ValueError:
                    hosts.add(item.lower().rstrip("."))

    # ---------------------------------------------------------------- authorization
    def assert_active(self, when: date | None = None) -> None:
        when = when or date.today()
        start = _parse_date(self.engagement["start"])
        end = _parse_date(self.engagement["end"])
        if when < start:
            raise ScopeError(f"engagement {self.engagement['id']} has not started (starts {start})")
        if when > end:
            raise ScopeError(f"engagement {self.engagement['id']} ended on {end}; authorization has expired")

    def resolve(self, target: str) -> list[str]:
        """Resolve a host to IPs; a literal IP returns itself. Used to scope-check names."""
        try:
            ipaddress.ip_address(target)
            return [target]
        except ValueError:
            pass
        try:
            return sorted({info[4][0] for info in socket.getaddrinfo(target, None)})
        except socket.gaierror:
            return []

    def in_scope_target(self, target: str) -> bool:
        """True only if the target (name or IP) is in scope and not excluded."""
        target = target.lower().rstrip(".")
        if target in self._out_hosts:
            return False
        ips = self.resolve(target)
        addrs = [ipaddress.ip_address(ip) for ip in ips]
        if any(a in n for a in addrs for n in self._out_nets):
            return False
        if target in self._in_hosts:
            return True
        return any(a in n for a in addrs for n in self._in_nets)

    def filter_targets(self, targets: list[str]) -> tuple[list[str], list[str]]:
        """Split targets into (authorized, refused)."""
        authorized, refused = [], []
        for t in targets:
            (authorized if self.in_scope_target(t) else refused).append(t)
        return authorized, refused

    def banner(self) -> str:
        e = self.engagement
        return (f"Engagement {e['id']} for {e['client']}\n"
                f"  Authorized by : {e['authorized_by']}\n"
                f"  Authorization : {e['authorization_ref']}\n"
                f"  Window        : {e['start']} to {e['end']}\n"
                f"  In scope      : {', '.join(self.in_scope)}\n"
                f"  Excluded      : {', '.join(self.out_of_scope) or 'none'}")


def _read_structured(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if path.endswith((".yaml", ".yml")):
        try:
            import yaml  # noqa: PLC0415
        except ImportError as exc:
            raise ScopeError("PyYAML is needed for YAML scope files (pip install pyyaml), "
                             "or use a .json scope file") from exc
        return yaml.safe_load(text)
    return json.loads(text)


def _parse_date(value: str) -> date:
    try:
        return datetime.strptime(str(value), "%Y-%m-%d").date()
    except ValueError as exc:
        raise ScopeError(f"dates must be YYYY-MM-DD, got {value!r}") from exc


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("scope_file")
    ap.add_argument("--check", metavar="TARGET", help="report whether a target is in scope")
    args = ap.parse_args(argv)
    try:
        scope = Scope.load(args.scope_file)
        scope.assert_active()
    except ScopeError as exc:
        print(f"scope error: {exc}", file=sys.stderr)
        return 2
    print(scope.banner())
    if args.check:
        ok = scope.in_scope_target(args.check)
        print(f"\n{args.check}: {'IN SCOPE' if ok else 'OUT OF SCOPE - refused'}")
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
