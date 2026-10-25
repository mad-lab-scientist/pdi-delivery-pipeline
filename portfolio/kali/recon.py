#!/usr/bin/env python3
"""Authorized reconnaissance orchestrator: scope-gated nmap service discovery for sanctioned engagements.

Every target is checked against the engagement scope (kali/lib/scope.py) before anything is sent.
Out-of-scope or excluded targets are refused, not scanned. The engagement must be inside its authorized
time window. Scanning is limited to host discovery and service/version detection with nmap's default+safe
scripts only; intrusive, brute-force, exploit and DoS script categories are rejected by design. Output is
written per engagement for reporting with parse_nmap.py.

    recon.py --scope scope.yaml --targets 192.0.2.0/24 --dry-run
    recon.py --scope scope.yaml --targets 192.0.2.0/24,app.example.com --top-ports 200 --i-am-authorized
    recon.py --scope scope.yaml --targets-file hosts.txt --out engagements/PDI-2026-014

This tool does not exploit anything. Use it only for assessments you are contractually authorized to run.
Requires nmap on PATH.
"""

from __future__ import annotations

import argparse
import datetime as dt
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from scope import Scope, ScopeError  # noqa: E402

FORBIDDEN_SCRIPT_TERMS = ("exploit", "dos", "brute", "intrusive", "malware", "vuln*")


def expand_targets(args) -> list[str]:
    targets: list[str] = []
    if args.targets:
        targets += [t.strip() for t in args.targets.split(",") if t.strip()]
    if args.targets_file:
        with open(args.targets_file, encoding="utf-8") as fh:
            targets += [line.split("#")[0].strip() for line in fh if line.split("#")[0].strip()]
    return targets


def build_nmap_command(scope: Scope, targets_file: Path, out_base: Path, args) -> list[str]:
    if args.discovery_only:
        cmd = ["nmap", "-sn"]  # host discovery only, no port scan
    else:
        cmd = ["nmap", "-sV"]  # service/version detection
        if args.skip_ping:
            cmd.append("-Pn")
        if args.top_ports:
            cmd += ["--top-ports", str(args.top_ports)]
        elif args.ports:
            cmd += ["-p", args.ports]
        # default + safe NSE only. guard_scripts() rejects anything intrusive.
        cmd += ["--script", "default,safe"]
    cmd += ["-T3"]
    max_rate = args.max_rate or scope.constraints.get("max_rate")
    if max_rate:
        cmd += ["--max-rate", str(int(max_rate))]
    cmd += ["-oA", str(out_base)]        # normal, XML and grepable output
    cmd += ["-iL", str(targets_file)]    # only the scope-approved targets
    return cmd


def guard_scripts(cmd: list[str]) -> None:
    joined = " ".join(cmd).lower()
    bad = [t for t in FORBIDDEN_SCRIPT_TERMS if t.strip("*") in joined]
    if bad:
        raise ScopeError(f"refusing to run: nmap arguments include forbidden category/term(s): {', '.join(bad)}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--scope", required=True, help="engagement scope file (kali/lib/scope.py format)")
    ap.add_argument("--targets", help="comma-separated hosts/CIDRs")
    ap.add_argument("--targets-file", help="file with one target per line")
    ap.add_argument("--top-ports", type=int, help="scan the N most common TCP ports")
    ap.add_argument("--ports", help="explicit ports, e.g. 22,80,443,8000-8100")
    ap.add_argument("--discovery-only", action="store_true", help="host discovery only (-sn), no port scan")
    ap.add_argument("--skip-ping", action="store_true", help="treat hosts as up (-Pn)")
    ap.add_argument("--max-rate", type=int, help="packets/sec ceiling (defaults to the scope constraint)")
    ap.add_argument("--out", default="engagements", help="output directory root")
    ap.add_argument("--dry-run", action="store_true", help="print the nmap command, scan nothing")
    ap.add_argument("--i-am-authorized", action="store_true",
                    help="confirm you have written authorization for this scope (required to run)")
    args = ap.parse_args(argv)

    try:
        scope = Scope.load(args.scope)
        scope.assert_active()
    except (ScopeError, OSError) as exc:
        print(f"scope error: {exc}", file=sys.stderr)
        return 2
    print(scope.banner())
    print()

    requested = expand_targets(args)
    if not requested:
        print("error: no targets given (--targets or --targets-file)", file=sys.stderr)
        return 2
    authorized, refused = scope.filter_targets(requested)
    for t in refused:
        print(f"  REFUSED (out of scope): {t}", file=sys.stderr)
    if not authorized:
        print("nothing in scope to scan; aborting.", file=sys.stderr)
        return 1
    print(f"In-scope targets to scan ({len(authorized)}): {', '.join(authorized)}")

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = Path(args.out) / scope.engagement["id"]
    out_dir.mkdir(parents=True, exist_ok=True)
    targets_file = out_dir / f"targets-{stamp}.txt"
    out_base = out_dir / f"recon-{stamp}"

    cmd = build_nmap_command(scope, targets_file, out_base, args)
    try:
        guard_scripts(cmd)
    except ScopeError as exc:
        print(exc, file=sys.stderr)
        return 2

    if args.dry_run:
        print("\n[dry-run] would write targets to", targets_file)
        print("[dry-run] would run:", " ".join(cmd))
        return 0
    if not args.i_am_authorized:
        print("\nRefusing to scan without --i-am-authorized. Confirm you hold written authorization for "
              "this engagement's scope, then re-run with --i-am-authorized.", file=sys.stderr)
        return 2
    if not shutil.which("nmap"):
        print("error: nmap is not installed/on PATH", file=sys.stderr)
        return 3

    targets_file.write_text("\n".join(authorized) + "\n", encoding="utf-8")
    print("\nrunning:", " ".join(cmd), "\n")
    result = subprocess.run(cmd, check=False)  # noqa: S603 - args built from validated, scoped inputs
    print(f"\noutput written to {out_base}.{{nmap,xml,gnmap}}")
    print(f"next: python parse_nmap.py {out_base}.xml --format markdown > {out_base}-report.md")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
