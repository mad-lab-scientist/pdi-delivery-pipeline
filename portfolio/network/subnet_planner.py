#!/usr/bin/env python3
"""VLSM subnet planner: carve a parent IPv4 block into right-sized subnets.

Give it a parent network and the host count each segment needs; it allocates the largest segments first so the
plan has no gaps, then prints network, mask, gateway, usable range, broadcast and utilisation for each subnet,
plus the address space left over.

    subnet_planner.py 10.20.0.0/16 users=500 servers=120 voice=200 mgmt=20 wan-link=2
    subnet_planner.py 172.16.0.0/22 users=200 printers=30 --gateway last --format csv > plan.csv
    subnet_planner.py                       # interactive: prompts for the parent network and each segment

Point-to-point links that need exactly 2 hosts get a /31 (RFC 3021) with --p2p-31, otherwise a /30.
"""

from __future__ import annotations

import argparse
import csv
import ipaddress
import json
import math
import sys
from dataclasses import asdict, dataclass

Network = ipaddress.IPv4Network


@dataclass(frozen=True)
class Requirement:
    name: str
    hosts: int


@dataclass(frozen=True)
class Subnet:
    name: str
    hosts_required: int
    network: str
    prefix: int
    netmask: str
    wildcard: str
    gateway: str
    first_usable: str
    last_usable: str
    broadcast: str
    usable_hosts: int
    utilisation_pct: float


def prefix_for(hosts: int, p2p_31: bool = False) -> int:
    """Smallest prefix whose usable host count covers `hosts`."""
    if hosts < 1:
        raise ValueError("a subnet needs at least 1 host")
    if hosts == 1:
        return 32
    if hosts == 2 and p2p_31:
        return 31
    # usable = 2^(32-prefix) - 2 (network and broadcast)
    return 32 - math.ceil(math.log2(hosts + 2))


def usable_range(net: Network) -> tuple[ipaddress.IPv4Address, ipaddress.IPv4Address, int]:
    """First usable, last usable and count; /31 and /32 follow RFC 3021 (every address usable)."""
    if net.prefixlen >= 31:
        return net.network_address, net.broadcast_address, net.num_addresses
    return net.network_address + 1, net.broadcast_address - 1, net.num_addresses - 2


def plan(parent: Network, requirements: list[Requirement], gateway: str = "first",
         p2p_31: bool = False) -> tuple[list[Subnet], list[Network]]:
    """Allocate largest-first; returns the subnets (in request order) and the free blocks left over."""
    names = [r.name for r in requirements]
    if len(set(names)) != len(names):
        raise ValueError("segment names must be unique")
    ordered = sorted(requirements, key=lambda r: (prefix_for(r.hosts, p2p_31), r.name))
    cursor = int(parent.network_address)
    end = int(parent.broadcast_address)
    allocated: dict[str, Subnet] = {}
    blocks: list[Network] = []
    for req in ordered:
        prefix = prefix_for(req.hosts, p2p_31)
        if prefix < parent.prefixlen:
            raise ValueError(f"{req.name}: {req.hosts} hosts need a /{prefix}, larger than {parent}")
        size = 2 ** (32 - prefix)
        start = (cursor + size - 1) // size * size  # align to the block size
        if start + size - 1 > end:
            raise ValueError(f"{parent} has no room left for {req.name} (/{prefix}); "
                             f"use a larger parent or fewer hosts")
        net = ipaddress.IPv4Network((start, prefix))
        first, last, usable = usable_range(net)
        gw = first if gateway == "first" else last
        allocated[req.name] = Subnet(
            name=req.name, hosts_required=req.hosts, network=str(net), prefix=prefix,
            netmask=str(net.netmask), wildcard=str(net.hostmask), gateway=str(gw) if prefix < 32 else "-",
            first_usable=str(first), last_usable=str(last), broadcast=str(net.broadcast_address),
            usable_hosts=usable, utilisation_pct=round(100 * req.hosts / usable, 1))
        blocks.append(net)
        cursor = start + size
    free = [parent]
    for used in blocks:
        free = [piece for block in free
                for piece in (block.address_exclude(used) if used.subnet_of(block) else [block])]
    return [allocated[n] for n in names], sorted(ipaddress.collapse_addresses(free))


def parse_requirement(text: str) -> Requirement:
    name, sep, count = text.partition("=")
    if not sep or not name.strip() or not count.strip().isdigit():
        raise argparse.ArgumentTypeError(f"expected name=hosts, got {text!r}")
    return Requirement(name.strip(), int(count))


def parse_parent(text: str) -> Network:
    try:
        net = ipaddress.ip_network(text.strip(), strict=True)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{text!r} is not a valid network ({exc}); "
                                         f"use the network address, e.g. 10.20.0.0/16") from exc
    if not isinstance(net, ipaddress.IPv4Network):
        raise argparse.ArgumentTypeError("VLSM planning here is IPv4; IPv6 subnets are simply /64s")
    return net


def ask(prompt: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{prompt}{suffix}: ").strip()
    return value or (default or "")


def interactive() -> tuple[Network, list[Requirement]]:
    while True:
        try:
            parent = parse_parent(ask("Parent network (CIDR)", "10.20.0.0/16"))
            break
        except argparse.ArgumentTypeError as exc:
            print(f"  {exc}")
    reqs: list[Requirement] = []
    print("Enter each segment; leave the name blank to finish.")
    while True:
        name = ask(f"  Segment {len(reqs) + 1} name")
        if not name:
            break
        count = ask(f"  Hosts needed in {name}")
        if not count.isdigit() or int(count) < 1:
            print("  hosts must be a positive whole number")
            continue
        reqs.append(Requirement(name, int(count)))
    return parent, reqs


def render(subnets: list[Subnet], free: list[Network], fmt: str, parent: Network) -> str:
    if fmt == "json":
        return json.dumps({"parent": str(parent), "subnets": [asdict(s) for s in subnets],
                           "free": [str(f) for f in free]}, indent=2)
    if fmt == "csv":
        out = []
        fields = list(asdict(subnets[0]).keys()) if subnets else []
        writer = csv.DictWriter(_Lines(out), fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for s in subnets:
            writer.writerow(asdict(s))
        return "".join(out).rstrip("\n")
    cols = [("Segment", "name"), ("Hosts", "hosts_required"), ("Network", "network"), ("Mask", "netmask"),
            ("Gateway", "gateway"), ("Usable range", None), ("Broadcast", "broadcast"),
            ("Usable", "usable_hosts"), ("Used %", "utilisation_pct")]
    rows = [[str(getattr(s, key)) if key else f"{s.first_usable} - {s.last_usable}" for _, key in cols]
            for s in subnets]
    if fmt == "markdown":
        lines = ["| " + " | ".join(h for h, _ in cols) + " |", "|" + "---|" * len(cols)]
        lines += ["| " + " | ".join(r) + " |" for r in rows]
    else:
        widths = [max(len(h), *(len(r[i]) for r in rows)) for i, (h, _) in enumerate(cols)]
        lines = ["  ".join(h.ljust(w) for (h, _), w in zip(cols, widths, strict=True)),
                 "  ".join("-" * w for w in widths)]
        lines += ["  ".join(c.ljust(w) for c, w in zip(r, widths, strict=True)) for r in rows]
    used = sum(2 ** (32 - s.prefix) for s in subnets)
    lines.append("")
    lines.append(f"{parent}: {used} of {parent.num_addresses} addresses allocated "
                 f"({100 * used / parent.num_addresses:.1f}%)")
    lines.append("Free blocks: " + (", ".join(str(f) for f in free) if free else "none"))
    return "\n".join(lines)


class _Lines:
    def __init__(self, sink: list[str]) -> None:
        self.sink = sink

    def write(self, text: str) -> None:
        self.sink.append(text)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("parent", nargs="?", type=parse_parent, help="parent network, e.g. 10.20.0.0/16")
    ap.add_argument("segments", nargs="*", type=parse_requirement, help="name=hosts, e.g. users=500")
    ap.add_argument("--gateway", choices=["first", "last"], default="first", help="gateway convention")
    ap.add_argument("--p2p-31", action="store_true", help="use /31 for 2-host point-to-point links")
    ap.add_argument("--format", choices=["table", "markdown", "csv", "json"], default="table")
    args = ap.parse_args(argv)
    parent, reqs = (args.parent, args.segments) if args.parent else interactive()
    if not reqs:
        ap.error("no segments given")
    try:
        subnets, free = plan(parent, reqs, args.gateway, args.p2p_31)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(render(subnets, free, args.format, parent))
    return 0


if __name__ == "__main__":
    sys.exit(main())
