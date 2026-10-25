#!/usr/bin/env python3
"""Lightweight syslog collector: UDP and TCP, RFC 5424 / RFC 3164 / FortiGate key=value, to daily JSON lines.

    syslog_receiver.py                                  # UDP+TCP on 0.0.0.0:5514, files in ./syslog/
    syslog_receiver.py --port 514 --out /var/log/remote --min-severity warning --print
    sudo setcap 'cap_net_bind_service=+ep' "$(readlink -f "$(which python3)")"   # to bind 514 without root

Each message becomes one JSON object (received_at, source, facility, severity, timestamp, host, app, procid,
msgid, message, and parsed key=value fields for FortiGate-style logs) in <out>/syslog-YYYY-MM-DD.jsonl, ready
for jq, a SIEM shipper or `grep`. TCP accepts newline framing and RFC 6587 octet counting.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import shlex
import sys
from datetime import UTC, datetime
from pathlib import Path

FACILITIES = ["kern", "user", "mail", "daemon", "auth", "syslog", "lpr", "news", "uucp", "cron", "authpriv",
              "ftp", "ntp", "audit", "alert", "clock", "local0", "local1", "local2", "local3", "local4", "local5",
              "local6", "local7"]
SEVERITIES = ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"]
RFC5424 = re.compile(r"^<(\d{1,3})>1 (\S+) (\S+) (\S+) (\S+) (\S+) (-|(?:\[.*?\])+)\s?(.*)$", re.S)
RFC3164 = re.compile(r"^<(\d{1,3})>(\w{3} [ \d]\d \d\d:\d\d:\d\d) (\S+) ([^:\[\s]+)(?:\[(\d+)\])?:? ?(.*)$", re.S)
PRI_ONLY = re.compile(r"^<(\d{1,3})>(.*)$", re.S)
KV = re.compile(r'\b[\w-]+=(?:"[^"]*"|\S+)')


def decode_pri(pri: int) -> tuple[str, str]:
    fac, sev = divmod(pri, 8)
    return (FACILITIES[fac] if fac < len(FACILITIES) else str(fac)), SEVERITIES[sev]


def parse(raw: str, source: str = "") -> dict:
    raw = raw.strip("\x00\r\n ")
    rec: dict = {"received_at": datetime.now(UTC).isoformat(timespec="seconds"), "source": source}
    m = RFC5424.match(raw)
    if m:
        pri, ts, host, app, procid, msgid, _sd, msg = m.groups()
        rec.update(timestamp=ts, host=host, app=app, procid=procid, msgid=msgid, message=msg.lstrip("\ufeff"))
    elif (m := RFC3164.match(raw)):
        pri, ts, host, app, procid, msg = m.groups()
        rec.update(timestamp=ts, host=host, app=app, procid=procid or "-", msgid="-", message=msg)
    elif (m := PRI_ONLY.match(raw)):
        pri, msg = m.groups()
        rec.update(timestamp="-", host=source, app="-", procid="-", msgid="-", message=msg)
    else:
        pri = "13"  # user.notice when the sender omits PRI (RFC 3164 4.3.3)
        rec.update(timestamp="-", host=source, app="-", procid="-", msgid="-", message=raw)
    rec["facility"], rec["severity"] = decode_pri(min(int(pri), 191))
    if rec["message"].count("=") >= 3 and KV.search(rec["message"]):  # FortiGate / key=value style logs
        try:
            rec["fields"] = dict(p.split("=", 1) for p in shlex.split(rec["message"]) if "=" in p)
            fields = rec["fields"]
            rec["host"] = fields.get("devname", rec["host"])
        except ValueError:
            pass
    return rec


class Sink:
    def __init__(self, out: Path, min_severity: str, echo: bool) -> None:
        self.out, self.echo = out, echo
        self.max_level = SEVERITIES.index(min_severity)
        self.day, self.fh = "", None
        out.mkdir(parents=True, exist_ok=True)

    def write(self, rec: dict) -> None:
        if SEVERITIES.index(rec["severity"]) > self.max_level:
            return
        day = rec["received_at"][:10]
        if day != self.day:
            if self.fh:
                self.fh.close()
            self.day, self.fh = day, open(self.out / f"syslog-{day}.jsonl", "a", encoding="utf-8")  # noqa: SIM115
        self.fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
        self.fh.flush()
        if self.echo:
            print(f"{rec['received_at']} {rec['source']:<15} {rec['facility']}.{rec['severity']:<7} "
                  f"{rec['host']} {rec['app']}: {rec['message'][:160]}")


class UDPProtocol(asyncio.DatagramProtocol):
    def __init__(self, sink: Sink) -> None:
        self.sink = sink

    def datagram_received(self, data: bytes, addr: tuple) -> None:
        self.sink.write(parse(data.decode("utf-8", "replace"), addr[0]))


async def handle_tcp(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, sink: Sink) -> None:
    peer = writer.get_extra_info("peername")[0]
    try:
        while True:
            first = await reader.read(1)
            if not first:
                break
            if first.isdigit():  # RFC 6587 octet counting: "<len> <msg>"
                digits = first + await reader.readuntil(b" ")
                frame = await reader.readexactly(int(digits[:-1]))
            else:
                frame = first + await reader.readuntil(b"\n")
            sink.write(parse(frame.decode("utf-8", "replace"), peer))
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ValueError, ConnectionError):
        pass
    finally:
        writer.close()


async def serve(args: argparse.Namespace) -> None:
    sink = Sink(Path(args.out), args.min_severity, args.print)
    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(lambda: UDPProtocol(sink), local_addr=(args.bind, args.port))
    server = await asyncio.start_server(lambda r, w: handle_tcp(r, w, sink), args.bind, args.port)
    print(f"listening on udp/tcp {args.bind}:{args.port}, writing {args.out}/syslog-<date>.jsonl", file=sys.stderr)
    try:
        async with server:
            await server.serve_forever()
    finally:
        transport.close()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--bind", default="0.0.0.0", help="listen address (default 0.0.0.0)")
    ap.add_argument("--port", type=int, default=5514, help="UDP and TCP port (default 5514)")
    ap.add_argument("--out", default="syslog", help="output directory (default ./syslog)")
    ap.add_argument("--min-severity", choices=SEVERITIES, default="debug", help="drop less severe messages")
    ap.add_argument("--print", action="store_true", help="also print each message")
    args = ap.parse_args(argv)
    try:
        asyncio.run(serve(args))
    except KeyboardInterrupt:
        pass
    except PermissionError:
        print(f"error: binding port {args.port} needs root or CAP_NET_BIND_SERVICE", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
