#!/usr/bin/env python3
"""Ping sweep: find live hosts in a subnet, with reverse DNS.

    ping_sweep.py 10.20.3.0/25
    ping_sweep.py 10.20.0.0/23 --count 2 --timeout 1 --csv > live-hosts.csv
    ping_sweep.py                          # prompts for the subnet

Uses the operating system's ping (Linux, macOS and Windows flags handled), so it needs no root privileges.
"""

from __future__ import annotations

import argparse
import asyncio
import ipaddress
import platform
import re
import socket
import sys
import time

RTT = re.compile(r"time[=<]\s*([\d.]+)\s*ms", re.IGNORECASE)


def ping_command(address: str, count: int, timeout: float) -> list[str]:
    system = platform.system()
    if system == "Windows":
        return ["ping", "-n", str(count), "-w", str(int(timeout * 1000)), address]
    if system == "Darwin":
        return ["ping", "-c", str(count), "-W", str(int(timeout * 1000)), address]
    return ["ping", "-c", str(count), "-W", str(max(1, round(timeout))), "-n", address]


async def ping(address: str, count: int, timeout: float, sem: asyncio.Semaphore) -> tuple[str, float | None]:
    async with sem:
        proc = await asyncio.create_subprocess_exec(
            *ping_command(address, count, timeout), stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
        text = out.decode(errors="replace")
        # Windows ping returns 0 for "Destination host unreachable" replies, so require an RTT in the output.
        match = RTT.search(text)
        return address, float(match.group(1)) if proc.returncode == 0 and match else None


def reverse_dns(address: str) -> str:
    try:
        return socket.gethostbyaddr(address)[0]
    except OSError:
        return ""


async def sweep(network: ipaddress.IPv4Network | ipaddress.IPv6Network, count: int, timeout: float,
                concurrency: int) -> list[tuple[str, float]]:
    sem = asyncio.Semaphore(concurrency)
    results = await asyncio.gather(*(ping(str(h), count, timeout, sem) for h in network.hosts()))
    return [(a, rtt) for a, rtt in results if rtt is not None]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("network", nargs="?", help="subnet in CIDR notation, e.g. 10.20.3.0/25")
    ap.add_argument("--count", type=int, default=1, help="echo requests per host (default 1)")
    ap.add_argument("--timeout", type=float, default=1.0, help="seconds to wait per reply (default 1)")
    ap.add_argument("--concurrency", type=int, default=128)
    ap.add_argument("--no-dns", action="store_true", help="skip reverse DNS lookups")
    ap.add_argument("--csv", action="store_true", help="CSV output (address,rtt_ms,hostname)")
    args = ap.parse_args(argv)
    text = args.network or input("Subnet to sweep (CIDR, e.g. 10.20.3.0/24): ").strip()
    try:
        network = ipaddress.ip_network(text, strict=False)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    if network.num_addresses > 65536:
        print("error: refusing to sweep more than a /16 in one run", file=sys.stderr)
        return 2
    started = time.perf_counter()
    alive = asyncio.run(sweep(network, args.count, args.timeout, args.concurrency))
    alive.sort(key=lambda item: ipaddress.ip_address(item[0]))
    if args.csv:
        print("address,rtt_ms,hostname")
    for address, rtt in alive:
        name = "" if args.no_dns else reverse_dns(address)
        print(f"{address},{rtt},{name}" if args.csv else f"{address:<16} {rtt:>7.1f} ms  {name}")
    if not args.csv:
        total = network.num_addresses - (2 if network.version == 4 and network.prefixlen < 31 else 0)
        print(f"\n{len(alive)} of {total} host(s) alive in {network} ({time.perf_counter() - started:.1f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
