#!/usr/bin/env python3
"""Asynchronous TCP connect scanner with optional banner grabbing.

    port_scan.py 10.20.3.0/25 --top 100
    port_scan.py fw01.corp.example 10.20.0.10 -p 22,80,443,8000-8100 --banners --format json
    port_scan.py 198.51.100.0/28 -p 443 --authorized      # public addresses need explicit authorisation

Uses full TCP connects (no raw sockets, no root), a concurrency limit and per-connection timeouts, so it is safe to
run from a jump host. Only scan networks you own or have written permission to test.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import csv
import ipaddress
import json
import socket
import sys
import time
from dataclasses import asdict, dataclass

TOP_PORTS = [
    21, 22, 23, 25, 53, 80, 81, 88, 110, 111, 135, 139, 143, 161, 389, 443, 445, 465, 514, 515, 587, 593, 631,
    636, 873, 902, 993, 995, 1080, 1194, 1433, 1521, 1723, 1883, 2049, 2082, 2083, 2222, 2375, 2376, 2379, 3000,
    3128, 3268, 3269, 3306, 3389, 3690, 4443, 4500, 5000, 5060, 5432, 5601, 5672, 5900, 5985, 5986, 6379, 6443,
    6667, 7001, 7443, 8000, 8008, 8080, 8081, 8088, 8443, 8834, 8888, 9000, 9090, 9092, 9100, 9200, 9300, 9443,
    10000, 10050, 10051, 10250, 11211, 15672, 27017, 27018, 50000, 50070, 4786, 8291, 8728, 10443, 541, 8013,
    830, 179, 520,
]
HTTP_PORTS = {80, 81, 3000, 5000, 8000, 8008, 8080, 8081, 8088, 8888, 9000, 9090}


@dataclass
class Result:
    host: str
    address: str
    port: int
    state: str
    service: str
    banner: str
    rtt_ms: float


def parse_ports(spec: str) -> list[int]:
    ports: set[int] = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        lo, sep, hi = part.partition("-")
        start, stop = int(lo), int(hi) if sep else int(lo)
        if not (1 <= start <= stop <= 65535):
            raise argparse.ArgumentTypeError(f"bad port range {part!r}")
        ports.update(range(start, stop + 1))
    return sorted(ports)


def expand_targets(specs: list[str]) -> list[tuple[str, str]]:
    """(label, address) pairs: CIDRs expand to hosts, names resolve once (first IPv4/IPv6 address)."""
    targets: list[tuple[str, str]] = []
    for spec in specs:
        try:
            net = ipaddress.ip_network(spec, strict=False)
            hosts = list(net.hosts()) if net.num_addresses > 1 else [net.network_address]
            targets += [(str(h), str(h)) for h in hosts]
            continue
        except ValueError:
            pass
        try:
            info = socket.getaddrinfo(spec, None, proto=socket.IPPROTO_TCP)
        except socket.gaierror as exc:
            print(f"warning: cannot resolve {spec}: {exc}", file=sys.stderr)
            continue
        targets.append((spec, info[0][4][0]))
    return targets


def service_name(port: int) -> str:
    try:
        return socket.getservbyport(port, "tcp")
    except OSError:
        return ""


async def probe(label: str, addr: str, port: int, timeout: float, banners: bool, sem: asyncio.Semaphore) -> Result:
    async with sem:
        start = time.perf_counter()
        try:
            reader, writer = await asyncio.wait_for(asyncio.open_connection(addr, port), timeout)
        except TimeoutError:
            return Result(label, addr, port, "filtered", "", "", 0.0)
        except ConnectionRefusedError:
            return Result(label, addr, port, "closed", "", "", 0.0)
        except OSError:
            return Result(label, addr, port, "unreachable", "", "", 0.0)
        rtt = round((time.perf_counter() - start) * 1000, 1)
        banner = ""
        if banners:
            try:
                if port in HTTP_PORTS:
                    writer.write(f"HEAD / HTTP/1.0\r\nHost: {label}\r\n\r\n".encode())
                    await writer.drain()
                data = await asyncio.wait_for(reader.read(256), timeout)
                banner = data.decode("utf-8", "replace").strip().splitlines()[0][:120] if data.strip() else ""
            except (TimeoutError, OSError, IndexError):
                pass
        writer.close()
        with contextlib.suppress(OSError):
            await writer.wait_closed()
        return Result(label, addr, port, "open", service_name(port), banner, rtt)


async def scan(targets: list[tuple[str, str]], ports: list[int], timeout: float, concurrency: int,
               banners: bool) -> list[Result]:
    sem = asyncio.Semaphore(concurrency)
    tasks = [probe(label, addr, port, timeout, banners, sem) for label, addr in targets for port in ports]
    return await asyncio.gather(*tasks)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("targets", nargs="+", help="hosts, IPs or CIDR blocks")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("-p", "--ports", type=parse_ports, help="e.g. 22,80,443,8000-8100")
    group.add_argument("--top", type=int, default=50, help="scan the N most common ports (default 50)")
    ap.add_argument("--timeout", type=float, default=1.0, help="seconds per connection (default 1.0)")
    ap.add_argument("--concurrency", type=int, default=400, help="parallel connections (default 400)")
    ap.add_argument("--banners", action="store_true", help="read a service banner from open ports")
    ap.add_argument("--show-closed", action="store_true", help="also list closed/filtered ports")
    ap.add_argument("--format", choices=["table", "json", "csv"], default="table")
    ap.add_argument("--authorized", action="store_true", help="confirm written permission for public targets")
    args = ap.parse_args(argv)

    targets = expand_targets(args.targets)
    if not targets:
        print("error: no targets", file=sys.stderr)
        return 2
    public = [a for _, a in targets if ipaddress.ip_address(a).is_global]
    if public and not args.authorized:
        print(f"error: {len(public)} public address(es) in scope (e.g. {public[0]}). Scan only what you are "
              f"authorised to test; re-run with --authorized to confirm.", file=sys.stderr)
        return 2
    ports = args.ports or TOP_PORTS[: max(1, args.top)]
    started = time.perf_counter()
    results = asyncio.run(scan(targets, ports, args.timeout, args.concurrency, args.banners))
    shown = [r for r in results if args.show_closed or r.state == "open"]
    shown.sort(key=lambda r: (ipaddress.ip_address(r.address), r.port))

    if args.format == "json":
        print(json.dumps([asdict(r) for r in shown], indent=2))
    elif args.format == "csv":
        writer = csv.DictWriter(sys.stdout, fieldnames=list(Result.__dataclass_fields__), lineterminator="\n")
        writer.writeheader()
        writer.writerows(asdict(r) for r in shown)
    else:
        for r in shown:
            label = r.host if r.host == r.address else f"{r.host} ({r.address})"
            print(f"{label:<40} {r.port:>5}/tcp  {r.state:<11} {r.service:<14} {r.rtt_ms:>7.1f} ms  {r.banner}")
        hosts_up = len({r.address for r in results if r.state == "open"})
        print(f"\n{len(targets)} host(s) x {len(ports)} port(s) in {time.perf_counter() - started:.1f}s: "
              f"{sum(r.state == 'open' for r in results)} open port(s) on {hosts_up} host(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
