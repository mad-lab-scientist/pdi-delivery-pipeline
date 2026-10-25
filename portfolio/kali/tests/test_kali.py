"""Unit tests for the Kali scope gate and nmap parser (stdlib unittest)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lib"))
sys.path.insert(0, str(HERE.parent))

import parse_nmap  # noqa: E402
from scope import Scope, ScopeError  # noqa: E402

FIXTURE = HERE / "fixtures" / "sample-nmap.xml"
SCOPE = {
    "engagement": {
        "id": "T-1", "client": "Example", "authorized_by": "CISO",
        "authorization_ref": "SOW-1", "start": "2026-10-01", "end": "2026-12-31",
    },
    "scope": {"in_scope": ["192.0.2.0/24", "app.example.com"], "out_of_scope": ["192.0.2.1", "192.0.2.200/29"]},
    "constraints": {"max_rate": 500},
}


def write_scope(data: dict) -> str:
    # delete=False so Scope.load can reopen the file by path after this returns.
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")  # noqa: SIM115
    json.dump(data, f)
    f.close()
    return f.name


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.scope = Scope.load(write_scope(SCOPE))

    def test_in_scope_and_exclusions(self):
        self.assertTrue(self.scope.in_scope_target("192.0.2.50"))
        self.assertTrue(self.scope.in_scope_target("app.example.com"))
        self.assertFalse(self.scope.in_scope_target("192.0.2.1"))       # explicitly excluded
        self.assertFalse(self.scope.in_scope_target("192.0.2.201"))     # in excluded /29
        self.assertFalse(self.scope.in_scope_target("203.0.113.5"))     # not in scope

    def test_filter_targets(self):
        authorized, refused = self.scope.filter_targets(["192.0.2.10", "192.0.2.1", "203.0.113.9"])
        self.assertEqual(authorized, ["192.0.2.10"])
        self.assertEqual(set(refused), {"192.0.2.1", "203.0.113.9"})

    def test_window_enforcement(self):
        self.scope.assert_active(date(2026, 11, 1))  # inside window: no raise
        with self.assertRaises(ScopeError):
            self.scope.assert_active(date(2026, 1, 1))   # before start
        with self.assertRaises(ScopeError):
            self.scope.assert_active(date(2027, 1, 1))   # after end

    def test_incomplete_authorization_rejected(self):
        bad = {"engagement": {"id": "x", "client": "y"}, "scope": {"in_scope": ["10.0.0.0/8"]}}
        with self.assertRaises(ScopeError):
            Scope.load(write_scope(bad))

    def test_empty_scope_rejected(self):
        bad = dict(SCOPE)
        bad = json.loads(json.dumps(SCOPE))
        bad["scope"]["in_scope"] = []
        with self.assertRaises(ScopeError):
            Scope.load(write_scope(bad))


class ParseNmapTests(unittest.TestCase):
    def test_parses_services_and_flags_exposures(self):
        rows = parse_nmap.parse(str(FIXTURE))
        by_port = {(r.host, r.port): r for r in rows}
        self.assertEqual(len(rows), 6)
        self.assertEqual(by_port[("192.0.2.10", 22)].product, "OpenSSH")
        self.assertEqual(by_port[("192.0.2.10", 23)].severity, "high")     # telnet
        self.assertEqual(by_port[("192.0.2.10", 3306)].severity, "high")   # mysql
        self.assertEqual(by_port[("192.0.2.11", 3389)].severity, "medium") # rdp
        self.assertEqual(by_port[("192.0.2.11", 161)].severity, "medium")  # snmp
        self.assertEqual(by_port[("192.0.2.10", 443)].severity, "info")    # http

    def test_markdown_and_csv_render(self):
        rows = parse_nmap.parse(str(FIXTURE))
        md = parse_nmap.render(rows, "markdown")
        self.assertIn("Notable exposures", md)
        self.assertIn("telnet", md)
        csv_out = parse_nmap.render(rows, "csv")
        expected_header = "host,hostname,port,protocol,state,service,product,version,severity,note"
        self.assertEqual(csv_out.splitlines()[0], expected_header)
