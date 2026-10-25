#!/usr/bin/env python3
"""DNS and email-security audit for a domain, with a dependency-free DNS client.

Checks NS/SOA, MX (incl. null MX), SPF (syntax, the all-qualifier and the RFC 7208 10-lookup limit, following
include:/redirect= recursively), DMARC policy, DKIM selectors you name, CAA, DNSSEC (DS at the parent and the
resolver's AD flag), MTA-STS and TLS-RPT.

    dns_audit.py example.com
    dns_audit.py example.com example.org --dkim selector1,selector2,google --resolver 9.9.9.9
    dns_audit.py example.com --format json --fail-on medium

The resolver speaks the DNS wire format directly (RFC 1035 with EDNS0, RFC 6891): UDP first, TCP when the
answer is truncated. Exit code 2 when a finding at or above --fail-on (default: high) exists, else 0.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import random
import re
import socket
import struct
import sys
from collections.abc import Callable
from dataclasses import asdict, dataclass, field

TYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "MX": 15, "TXT": 16, "AAAA": 28, "DS": 43, "DNSKEY": 48,
         "CAA": 257}
TYPE_NAMES = {v: k for k, v in TYPES.items()}
RCODES = {0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN", 4: "NOTIMP", 5: "REFUSED"}
SEVERITY = ["info", "low", "medium", "high", "critical"]


class DNSError(Exception):
    pass


@dataclass
class Answer:
    rcode: str
    authenticated: bool
    records: list  # parsed RDATA values for the requested type


# ---------------------------------------------------------------- wire format
def encode_name(name: str) -> bytes:
    out = b""
    for label in name.rstrip(".").split("."):
        if not label:
            continue
        raw = label.encode("idna")
        if len(raw) > 63:
            raise DNSError(f"label too long: {label}")
        out += bytes([len(raw)]) + raw
    return out + b"\x00"


def build_query(name: str, qtype: int, qid: int, dnssec_ok: bool = True) -> bytes:
    flags = 0x0100 | 0x0020  # RD + AD (ask the resolver to report DNSSEC validation)
    header = struct.pack("!HHHHHH", qid, flags, 1, 0, 0, 1)
    question = encode_name(name) + struct.pack("!HH", qtype, 1)
    opt = b"\x00" + struct.pack("!HHIH", 41, 1232, 0x8000 if dnssec_ok else 0, 0)  # EDNS0, DO bit
    return header + question + opt


def read_name(msg: bytes, offset: int) -> tuple[str, int]:
    labels: list[str] = []
    jumped, end, hops = False, offset, 0
    while True:
        if offset >= len(msg):
            raise DNSError("truncated name")
        length = msg[offset]
        if length & 0xC0 == 0xC0:  # compression pointer
            if offset + 1 >= len(msg):
                raise DNSError("truncated pointer")
            if not jumped:
                end = offset + 2
            offset = ((length & 0x3F) << 8) | msg[offset + 1]
            jumped, hops = True, hops + 1
            if hops > 64:
                raise DNSError("compression loop")
            continue
        if length == 0:
            return ".".join(labels), (end if jumped else offset + 1)
        labels.append(msg[offset + 1: offset + 1 + length].decode("ascii", "replace"))
        offset += 1 + length


def parse_rdata(msg: bytes, rtype: int, start: int, length: int):
    data = msg[start: start + length]
    if rtype == TYPES["A"]:
        return str(ipaddress.IPv4Address(data))
    if rtype == TYPES["AAAA"]:
        return str(ipaddress.IPv6Address(data))
    if rtype in (TYPES["NS"], TYPES["CNAME"]):
        return read_name(msg, start)[0]
    if rtype == TYPES["MX"]:
        return (struct.unpack("!H", data[:2])[0], read_name(msg, start + 2)[0])
    if rtype == TYPES["TXT"]:
        parts, i = [], 0
        while i < len(data):
            n = data[i]
            parts.append(data[i + 1: i + 1 + n].decode("utf-8", "replace"))
            i += 1 + n
        return "".join(parts)  # RFC 7208 3.3: multiple strings are concatenated without spaces
    if rtype == TYPES["SOA"]:
        mname, off = read_name(msg, start)
        rname, off = read_name(msg, off)
        serial, refresh, retry, expire, minimum = struct.unpack("!IIIII", msg[off: off + 20])
        return {"mname": mname, "rname": rname, "serial": serial, "refresh": refresh, "retry": retry,
                "expire": expire, "minimum": minimum}
    if rtype == TYPES["CAA"]:
        tag_len = data[1]
        return {"flags": data[0], "tag": data[2: 2 + tag_len].decode(), "value": data[2 + tag_len:].decode()}
    if rtype == TYPES["DS"]:
        tag, alg, dtype = struct.unpack("!HBB", data[:4])
        return {"key_tag": tag, "algorithm": alg, "digest_type": dtype, "digest": data[4:].hex()}
    return data.hex()


def parse_response(msg: bytes, qid: int, qtype: int) -> Answer:
    if len(msg) < 12:
        raise DNSError("short response")
    rid, flags, qd, an, _ns, _ar = struct.unpack("!HHHHHH", msg[:12])
    if rid != qid:
        raise DNSError("response ID mismatch")
    offset = 12
    for _ in range(qd):
        offset = read_name(msg, offset)[1] + 4
    records = []
    for _ in range(an):
        _, offset = read_name(msg, offset)
        rtype, _cls, _ttl, rdlen = struct.unpack("!HHIH", msg[offset: offset + 10])
        offset += 10
        if rtype == qtype:
            records.append(parse_rdata(msg, rtype, offset, rdlen))
        offset += rdlen
    return Answer(RCODES.get(flags & 0x000F, str(flags & 0x000F)), bool(flags & 0x0020), records)


def system_resolver() -> str:
    try:
        with open("/etc/resolv.conf", encoding="utf-8") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 2 and parts[0] == "nameserver":
                    return parts[1]
    except OSError:
        pass
    return "1.1.1.1"


class Resolver:
    def __init__(self, server: str | None = None, timeout: float = 3.0) -> None:
        self.server = server or system_resolver()
        self.timeout = timeout
        self.cache: dict[tuple[str, int], Answer] = {}

    def query(self, name: str, rtype: str) -> Answer:
        key = (name.lower().rstrip("."), TYPES[rtype])
        if key not in self.cache:
            self.cache[key] = self._ask(*key)
        return self.cache[key]

    def _ask(self, name: str, qtype: int) -> Answer:
        qid = random.SystemRandom().randrange(1, 65535)
        packet = build_query(name, qtype, qid)
        family = socket.AF_INET6 if ":" in self.server else socket.AF_INET
        with socket.socket(family, socket.SOCK_DGRAM) as udp:
            udp.settimeout(self.timeout)
            udp.sendto(packet, (self.server, 53))
            data, _ = udp.recvfrom(4096)
        if struct.unpack("!H", data[2:4])[0] & 0x0200:  # TC: retry over TCP
            with socket.create_connection((self.server, 53), timeout=self.timeout) as tcp:
                tcp.sendall(struct.pack("!H", len(packet)) + packet)
                size = struct.unpack("!H", _recv_exact(tcp, 2))[0]
                data = _recv_exact(tcp, size)
        return parse_response(data, qid, qtype)


def _recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise DNSError("connection closed")
        buf += chunk
    return buf


# ---------------------------------------------------------------- checks
@dataclass
class Finding:
    check: str
    severity: str
    message: str


@dataclass
class DomainReport:
    domain: str
    records: dict = field(default_factory=dict)
    findings: list[Finding] = field(default_factory=list)

    def add(self, check: str, severity: str, message: str) -> None:
        self.findings.append(Finding(check, severity, message))


Lookup = Callable[[str, str], Answer]
LOOKUP_TERMS = {"include", "a", "mx", "ptr", "exists", "redirect"}  # RFC 7208 4.6.4: these cost a DNS query


def term_name(term: str) -> str:
    """'include' for '~include:x', 'a' for 'a/24', 'redirect' for 'redirect=x', 'all' for '-all'."""
    return re.split(r"[:/=]", term.lstrip("+-~?").lower(), maxsplit=1)[0]


def spf_records(lookup: Lookup, domain: str) -> list[str]:
    return [t for t in lookup(domain, "TXT").records if t.lower().startswith("v=spf1")]


def spf_lookups(lookup: Lookup, domain: str, seen: set[str] | None = None, depth: int = 0) -> tuple[int, list[str]]:
    """DNS-querying terms in the SPF tree (RFC 7208 4.6.4 limit is 10), plus notes about problems found."""
    seen = seen if seen is not None else set()
    notes: list[str] = []
    if domain in seen or depth > 10:
        return 0, [f"SPF loop or excessive nesting at {domain}"]
    seen.add(domain)
    records = spf_records(lookup, domain)
    if len(records) != 1:
        return 0, [f"{domain}: {len(records)} SPF records"] if depth else []
    count = 0
    for term in records[0].split()[1:]:
        name = term_name(term)
        if name in LOOKUP_TERMS:
            count += 1
            bare = term.lstrip("+-~?").lower()
            target = bare.split(":" if name == "include" else "=", 1)[1] if name in ("include", "redirect") else None
            if target and "%" not in target:  # macros can't be expanded statically
                sub, sub_notes = spf_lookups(lookup, target, seen, depth + 1)
                count += sub
                notes += sub_notes
    return count, notes


def check_spf(rep: DomainReport, lookup: Lookup, has_mail: bool) -> None:
    records = spf_records(lookup, rep.domain)
    rep.records["spf"] = records
    if not records:
        if has_mail:
            rep.add("spf", "high", "no SPF record; anyone can send mail as this domain")
        else:
            rep.add("spf", "medium", "no SPF record; for a domain that sends no mail publish 'v=spf1 -all'")
        return
    if len(records) > 1:
        rep.add("spf", "high", f"{len(records)} SPF records (RFC 7208 permerror); merge them into one")
        return
    terms = records[0].split()[1:]
    alls = [t for t in terms if term_name(t) == "all"]
    redirect = any(term_name(t) == "redirect" for t in terms)
    if not alls and not redirect:
        rep.add("spf", "medium", "SPF has no 'all' mechanism; unmatched senders get neutral")
    elif alls:
        q = alls[-1][0] if alls[-1][0] in "+-~?" else "+"
        if q == "+":
            rep.add("spf", "critical", "SPF ends in '+all': every server on the internet is authorised")
        elif q == "?":
            rep.add("spf", "medium", "SPF ends in '?all' (neutral); use '~all' or '-all'")
        elif q == "~":
            rep.add("spf", "info", "SPF ends in '~all' (softfail); '-all' once DMARC reports are clean")
    if any(term_name(t) == "ptr" for t in terms):
        rep.add("spf", "low", "SPF uses the deprecated 'ptr' mechanism (RFC 7208 5.5)")
    count, notes = spf_lookups(lookup, rep.domain)
    rep.records["spf_dns_lookups"] = count
    for note in notes:
        rep.add("spf", "medium", note)
    if count > 10:
        rep.add("spf", "high", f"SPF needs {count} DNS lookups; the limit is 10 (permerror at receivers)")


def tags(record: str) -> dict[str, str]:
    out = {}
    for part in record.split(";"):
        key, sep, value = part.strip().partition("=")
        if sep:
            out[key.strip().lower()] = value.strip()
    return out


def check_dmarc(rep: DomainReport, lookup: Lookup) -> None:
    records = [t for t in lookup(f"_dmarc.{rep.domain}", "TXT").records if t.lower().startswith("v=dmarc1")]
    rep.records["dmarc"] = records
    if not records:
        rep.add("dmarc", "high", "no DMARC record at _dmarc; spoofed mail is not rejected or reported")
        return
    if len(records) > 1:
        rep.add("dmarc", "high", "multiple DMARC records; receivers ignore all of them")
        return
    t = tags(records[0])
    policy = t.get("p", "").lower()
    if policy == "none":
        rep.add("dmarc", "medium", "DMARC p=none only monitors; move to quarantine, then reject")
    elif policy not in ("quarantine", "reject"):
        rep.add("dmarc", "high", f"DMARC policy missing or invalid (p={policy or '?'})")
    if "rua" not in t:
        rep.add("dmarc", "low", "no rua= aggregate report address; you cannot see who sends as you")
    if t.get("pct", "100") != "100":
        rep.add("dmarc", "low", f"DMARC applies to pct={t['pct']}% of mail only")


def audit(domain: str, resolver: Resolver, dkim_selectors: list[str]) -> DomainReport:
    rep = DomainReport(domain=domain.lower().rstrip("."))
    lookup = resolver.query
    soa = lookup(rep.domain, "SOA")
    if soa.rcode == "NXDOMAIN":
        rep.add("domain", "critical", "domain does not exist (NXDOMAIN)")
        return rep
    rep.records["soa"] = soa.records[0] if soa.records else None
    ns = lookup(rep.domain, "NS").records
    rep.records["ns"] = sorted(ns)
    if len(ns) < 2:
        rep.add("ns", "medium", f"{len(ns)} name server(s); RFC 1034 expects at least two")
    mx = sorted(lookup(rep.domain, "MX").records)
    rep.records["mx"] = [f"{p} {h or '.'}" for p, h in mx]
    null_mx = len(mx) == 1 and mx[0][1] in ("", ".")
    has_mail = bool(mx) and not null_mx
    if not mx:
        rep.add("mx", "info", "no MX record (mail falls back to the A record); publish a null MX if unused")
    check_spf(rep, lookup, has_mail)
    check_dmarc(rep, lookup)
    for sel in dkim_selectors:
        recs = [t for t in lookup(f"{sel}._domainkey.{rep.domain}", "TXT").records if "p=" in t]
        rep.records.setdefault("dkim", {})[sel] = bool(recs)
        if not recs:
            rep.add("dkim", "medium", f"no DKIM key at selector '{sel}'")
        elif tags(recs[0]).get("p", "x") == "":
            rep.add("dkim", "info", f"DKIM selector '{sel}' is revoked (empty p=)")
    caa = lookup(rep.domain, "CAA").records
    rep.records["caa"] = [f"{c['flags']} {c['tag']} \"{c['value']}\"" for c in caa]
    if not caa:
        rep.add("caa", "low", "no CAA record; any public CA may issue certificates for this domain")
    ds = lookup(rep.domain, "DS").records
    validated = lookup(rep.domain, "SOA").authenticated
    rep.records["dnssec"] = {"ds_records": len(ds), "resolver_validated": validated}
    if not ds:
        rep.add("dnssec", "low", "not DNSSEC-signed (no DS record at the parent zone)")
    elif not validated:
        rep.add("dnssec", "info", "DS exists, but this resolver did not set AD (it may not validate)")
    if has_mail:
        if not any(t.startswith("v=STSv1") for t in lookup(f"_mta-sts.{rep.domain}", "TXT").records):
            rep.add("mta-sts", "low", "no MTA-STS policy; inbound SMTP TLS can be downgraded")
        if not any(t.startswith("v=TLSRPTv1") for t in lookup(f"_smtp._tls.{rep.domain}", "TXT").records):
            rep.add("tls-rpt", "info", "no TLS-RPT record for SMTP TLS failure reports")
    return rep


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("domains", nargs="*", help="domains to audit")
    ap.add_argument("--dkim", default="", help="comma-separated DKIM selectors to check")
    ap.add_argument("--resolver", default=os.environ.get("DNS_RESOLVER"), help="resolver IP (default: system)")
    ap.add_argument("--timeout", type=float, default=3.0)
    ap.add_argument("--format", choices=["table", "json"], default="table")
    ap.add_argument("--fail-on", choices=SEVERITY, default="high")
    args = ap.parse_args(argv)
    domains = args.domains or [input("Domain to audit: ").strip()]
    resolver = Resolver(args.resolver, args.timeout)
    selectors = [s.strip() for s in args.dkim.split(",") if s.strip()]
    reports = []
    for domain in domains:
        try:
            reports.append(audit(domain, resolver, selectors))
        except (OSError, DNSError) as exc:
            print(f"error: {domain}: {exc} (resolver {resolver.server})", file=sys.stderr)
            return 3
    if args.format == "json":
        print(json.dumps([asdict(r) for r in reports], indent=2, default=str))
    else:
        for r in reports:
            print(f"== {r.domain}  (resolver {resolver.server})")
            for key in ("ns", "mx", "spf", "dmarc", "caa", "dnssec"):
                if key in r.records:
                    print(f"   {key:<7} {r.records[key]}")
            order = sorted(r.findings, key=lambda f: -SEVERITY.index(f.severity))
            for f in order:
                print(f"   [{f.severity.upper():<8}] {f.check:<8} {f.message}")
            if not order:
                print("   no findings")
            print()
    threshold = SEVERITY.index(args.fail_on)
    return 2 if any(SEVERITY.index(f.severity) >= threshold for r in reports for f in r.findings) else 0


if __name__ == "__main__":
    sys.exit(main())
