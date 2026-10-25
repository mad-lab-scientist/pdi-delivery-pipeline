#!/usr/bin/env python3
"""Multi-vendor configuration backup over SSH, with change detection and optional git history.

Inventory is a CSV file:  name,host,device_type[,port]   (device_type as Netmiko names it)

    name,host,device_type,port
    core-sw01,10.20.3.2,cisco_ios,22
    edge-fw01,10.20.3.1,fortinet,22
    dc-leaf01,10.20.3.10,arista_eos,22

    device_backup.py inventory.csv --out backups/ --git
    NET_USERNAME=netops device_backup.py inventory.csv --workers 8     # password prompted (never echoed)

Credentials come from NET_USERNAME / NET_PASSWORD / NET_SECRET or interactive prompts; they are never written to
disk or logs. A device's file is rewritten only when its configuration really changed: volatile lines (timestamps,
NTP drift, FortiOS re-encrypted secrets) are ignored when comparing. Requires: pip install netmiko
"""

from __future__ import annotations

import argparse
import csv
import difflib
import getpass
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

COMMANDS = {
    "cisco_ios": "show running-config", "cisco_xe": "show running-config", "cisco_nxos": "show running-config",
    "cisco_asa": "show running-config", "arista_eos": "show running-config", "hp_procurve": "show running-config",
    "aruba_aoscx": "show running-config", "dell_os10": "show running-config", "fortinet": "show full-configuration",
    "juniper_junos": "show configuration | display set", "paloalto_panos": "show config running",
    "mikrotik_routeros": "/export terse", "ubiquiti_edgeswitch": "show running-config",
}
VOLATILE = [
    r"^! Last configuration change at .*", r"^! NVRAM config last updated at .*", r"^ntp clock-period \d+",
    r"^Building configuration\.\.\.", r"^Current configuration : \d+ bytes", r"^## Last commit: .*",
    r"^! Time: .*", r"^# \w{3}/\d{2}/\d{4} .* by RouterOS .*", r"^# \d{4}-\d{2}-\d{2} .* by RouterOS .*",
    r"^#conf_file_ver=\d+", r"^: Written by .* at .*", r"^Cryptochecksum:.*",
]
ENC = re.compile(r"(\bENC\s+)\S+")
SECRETS = [
    (re.compile(r"^(\s*(enable )?(secret|password)\s+(\d+\s+)?)\S+.*$", re.M), r"\1<removed>"),
    (re.compile(r"^(\s*username \S+ .*?(secret|password)\s+(\d+\s+)?)\S+", re.M), r"\1<removed>"),
    (re.compile(r"^(\s*snmp-server community )\S+", re.M), r"\1<removed>"),
    (re.compile(r"^(\s*set (password|passwd|psksecret|secret|private-key|key)\s+).*$", re.M), r"\1<removed>"),
    (re.compile(r"^(\s*key-string\s+).*$", re.M), r"\1<removed>"),
]


@dataclass(frozen=True)
class Device:
    name: str
    host: str
    device_type: str
    port: int = 22


def load_inventory(path: str) -> list[Device]:
    devices = []
    with open(path, newline="", encoding="utf-8") as fh:
        for row_no, row in enumerate(csv.DictReader(fh), start=2):
            name, host, dtype = (row.get(k, "").strip() for k in ("name", "host", "device_type"))
            if not (name and host and dtype):
                raise ValueError(f"{path}:{row_no}: name, host and device_type are required")
            if dtype not in COMMANDS:
                raise ValueError(f"{path}:{row_no}: unsupported device_type {dtype!r} "
                                 f"(supported: {', '.join(sorted(COMMANDS))})")
            if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
                raise ValueError(f"{path}:{row_no}: device name {name!r} is not a safe file name")
            devices.append(Device(name, host, dtype, int(row.get("port") or 22)))
    if len({d.name for d in devices}) != len(devices):
        raise ValueError(f"{path}: duplicate device names")
    return devices


def normalise(text: str) -> str:
    """Config with volatile lines removed, for change comparison only."""
    lines = [ln for ln in text.replace("\r\n", "\n").split("\n")
             if not any(re.match(p, ln) for p in VOLATILE)]
    return ENC.sub(r"\1<enc>", "\n".join(lines)).strip() + "\n"


def redact(text: str) -> str:
    for pattern, repl in SECRETS:
        text = pattern.sub(repl, text)
    return ENC.sub(r"\1<removed>", text)


def fetch(device: Device, username: str, password: str, secret: str, timeout: int) -> str:
    from netmiko import ConnectHandler  # noqa: PLC0415 - lazy, so --help works without netmiko installed

    params = {"device_type": device.device_type, "host": device.host, "port": device.port,
              "username": username, "password": password, "conn_timeout": timeout, "fast_cli": False}
    if secret:
        params["secret"] = secret
    with ConnectHandler(**params) as conn:
        if secret and device.device_type.startswith(("cisco", "arista", "dell")):
            conn.enable()
        return conn.send_command(COMMANDS[device.device_type], read_timeout=180)


def save(device: Device, config: str, out: Path, do_redact: bool) -> tuple[str, int]:
    """Writes the file if the configuration changed; returns (status, changed line count)."""
    if do_redact:
        config = redact(config)
    target = out / f"{device.name}.cfg"
    if target.exists():
        old = target.read_text(encoding="utf-8")
        if normalise(old) == normalise(config):
            return "unchanged", 0
        diff = difflib.unified_diff(normalise(old).splitlines(), normalise(config).splitlines(), lineterm="", n=0)
        changed = sum(1 for ln in diff if ln[:1] in "+-" and not ln.startswith(("+++", "---")))
        status = "changed"
    else:
        changed, status = config.count("\n"), "new"
    target.write_text(config if config.endswith("\n") else config + "\n", encoding="utf-8")
    target.chmod(0o600)
    return status, changed


def git_commit(out: Path, summary: list[str]) -> None:
    if not (out / ".git").exists():
        subprocess.run(["git", "init", "-q"], cwd=out, check=True)
    subprocess.run(["git", "add", "-A"], cwd=out, check=True)
    if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=out, check=False).returncode == 0:
        return
    msg = f"Config backup {datetime.now():%Y-%m-%d %H:%M}\n\n" + "\n".join(summary)
    subprocess.run(["git", "-c", "user.name=device-backup", "-c", "user.email=device-backup@localhost",
                    "commit", "-q", "-m", msg], cwd=out, check=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("inventory", help="CSV with name,host,device_type[,port]")
    ap.add_argument("--out", default="backups", help="output directory (default: backups)")
    ap.add_argument("--workers", type=int, default=6, help="parallel SSH sessions (default 6)")
    ap.add_argument("--timeout", type=int, default=20, help="connection timeout in seconds")
    ap.add_argument("--redact", action="store_true", help="remove secrets from saved files (not restorable)")
    ap.add_argument("--git", action="store_true", help="commit changes to a git repository in --out")
    args = ap.parse_args(argv)
    try:
        devices = load_inventory(args.inventory)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    username = os.environ.get("NET_USERNAME") or input("SSH username: ").strip()
    password = os.environ.get("NET_PASSWORD") or getpass.getpass(f"SSH password for {username}: ")
    secret = os.environ.get("NET_SECRET", "")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    summary, failures = [], 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(fetch, d, username, password, secret, args.timeout): d for d in devices}
        for job in as_completed(jobs):
            device = jobs[job]
            try:
                status, changed = save(device, job.result(), out, args.redact)
                line = f"{device.name:<24} {status:<10} {changed} line(s)"
            except Exception as exc:  # noqa: BLE001 - report every device, keep going
                failures += 1
                line = f"{device.name:<24} FAILED     {type(exc).__name__}: {str(exc).splitlines()[0][:100]}"
            print(line)
            summary.append(line)
    if args.git:
        git_commit(out, sorted(summary))
    print(f"\n{len(devices) - failures}/{len(devices)} device(s) backed up to {out}/")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
