"""Unit tests for the network tools (stdlib unittest).

Run:  cd network/tests && python -m unittest discover -p 'test_*.py'
"""

from __future__ import annotations

import ipaddress
import struct
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
FIXTURES = HERE / "fixtures"

import cisco_ios_audit  # noqa: E402
import device_backup  # noqa: E402
import dns_audit  # noqa: E402
import fortigate_audit  # noqa: E402
import subnet_planner  # noqa: E402


class SubnetPlannerTests(unittest.TestCase):
    def test_prefix_for(self):
        self.assertEqual(subnet_planner.prefix_for(500), 23)
        self.assertEqual(subnet_planner.prefix_for(254), 24)
        self.assertEqual(subnet_planner.prefix_for(2), 30)
        self.assertEqual(subnet_planner.prefix_for(2, p2p_31=True), 31)
        self.assertEqual(subnet_planner.prefix_for(1), 32)

    def test_vlsm_allocation_is_largest_first_and_non_overlapping(self):
        parent = ipaddress.ip_network("10.20.0.0/16")
        reqs = [subnet_planner.Requirement(n, h) for n, h in
                [("users", 500), ("voice", 200), ("servers", 120), ("mgmt", 20), ("link", 2)]]
        subnets, free = subnet_planner.plan(parent, reqs, p2p_31=True)
        by = {s.name: s for s in subnets}
        self.assertEqual(by["users"].network, "10.20.0.0/23")
        self.assertEqual(by["link"].prefix, 31)
        nets = [ipaddress.ip_network(s.network) for s in subnets]
        for i, a in enumerate(nets):
            for b in nets[i + 1:]:
                self.assertFalse(a.overlaps(b))
        used = sum(n.num_addresses for n in nets) + sum(f.num_addresses for f in free)
        self.assertEqual(used, parent.num_addresses)

    def test_overflow_raises(self):
        with self.assertRaises(ValueError):
            subnet_planner.plan(ipaddress.ip_network("172.16.0.0/24"), [subnet_planner.Requirement("big", 300)])


class DnsWireFormatTests(unittest.TestCase):
    def test_query_encoding(self):
        q = dns_audit.build_query("example.com", dns_audit.TYPES["MX"], 0x1234)
        self.assertEqual(q[:2], struct.pack("!H", 0x1234))
        self.assertEqual(q[12:25], b"\x07example\x03com\x00")

    def test_parse_mx_with_compression(self):
        qid, qtype = 7, dns_audit.TYPES["MX"]
        msg = struct.pack("!HHHHHH", qid, 0x81A0, 1, 1, 0, 0)
        msg += dns_audit.encode_name("example.com") + struct.pack("!HH", qtype, 1)
        rdata = struct.pack("!H", 10) + b"\x04mail\xc0\x0c"
        msg += b"\xc0\x0c" + struct.pack("!HHIH", qtype, 1, 300, len(rdata)) + rdata
        ans = dns_audit.parse_response(msg, qid, qtype)
        self.assertEqual(ans.records, [(10, "mail.example.com")])

    def test_compression_loop_rejected(self):
        with self.assertRaises(dns_audit.DNSError):
            dns_audit.read_name(b"\x00" * 12 + b"\xc0\x0c", 12)


class SpfDmarcTests(unittest.TestCase):
    def fake(self, zone):
        def lookup(name, rtype):
            return dns_audit.Answer("NOERROR", False, zone.get((name, rtype), []))
        return lookup

    def test_spf_lookup_counting(self):
        zone = {("example.com", "TXT"): ["v=spf1 a mx include:_spf.x ip4:1.2.3.0/24 -all"],
                ("_spf.x", "TXT"): ["v=spf1 include:a.x ~all"],
                ("a.x", "TXT"): ["v=spf1 ip4:5.6.7.0/24 -all"]}
        count, notes = dns_audit.spf_lookups(self.fake(zone), "example.com")
        self.assertEqual(count, 4)   # a, mx, include -> include a
        self.assertEqual(notes, [])

    def test_spf_plus_all_is_critical(self):
        rep = dns_audit.DomainReport("example.com")
        dns_audit.check_spf(rep, self.fake({("example.com", "TXT"): ["v=spf1 +all"]}), has_mail=True)
        self.assertEqual(rep.findings[0].severity, "critical")

    def test_dmarc_none_is_flagged(self):
        rep = dns_audit.DomainReport("example.com")
        dns_audit.check_dmarc(rep, self.fake({("_dmarc.example.com", "TXT"): ["v=DMARC1; p=none"]}))
        self.assertTrue(any("quarantine" in f.message for f in rep.findings))


class FortiGateAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root, cls.meta = fortigate_audit.parse_config((FIXTURES / "fortigate-sample.conf").read_text())
        wans = fortigate_audit.wan_interfaces(root, [])
        cls.findings = fortigate_audit.audit_policies(root, wans) + fortigate_audit.audit_system(root, wans)

    def ids(self, obj):
        return {f.id for f in self.findings if f.object == obj}

    def test_header(self):
        self.assertEqual(self.meta["model"], "FGT60F")

    def test_any_any_policy_flagged(self):
        self.assertIn("FGT-POL-001", self.ids('policy 4 "Any-Any"'))

    def test_shadowed_deny_is_high(self):
        shadow = {f.object: f for f in self.findings if f.id == "FGT-POL-020"}
        self.assertEqual(shadow['policy 6 "Block-RDP"'].severity, "high")

    def test_forticloud_sso_and_wan_admin(self):
        ids = {f.id for f in self.findings}
        self.assertTrue({"FGT-SYS-001", "FGT-SYS-010", "FGT-VPN-001"} <= ids)


class CiscoAuditTests(unittest.TestCase):
    def test_weak_config_findings(self):
        findings = cisco_ios_audit.audit("x", (FIXTURES / "ios-weak.cfg").read_text())
        ids = {f.id for f in findings}
        self.assertTrue({"IOS-004", "IOS-020", "IOS-030", "IOS-040"} <= ids)

    def test_hardened_config_is_clean(self):
        findings = cisco_ios_audit.audit("x", (FIXTURES / "ios-hardened.cfg").read_text())
        self.assertEqual(findings, [])
        self.assertEqual(cisco_ios_audit.score(findings), 100)


class DeviceBackupTests(unittest.TestCase):
    def test_inventory_rejects_unsafe_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp, "inv.csv")
            bad.write_text("name,host,device_type\n../etc,10.0.0.1,cisco_ios\n")
            with self.assertRaises(ValueError):
                device_backup.load_inventory(str(bad))

    def test_volatile_lines_ignored_in_change_detection(self):
        a = "! Last configuration change at 09:00:00 UTC\nhostname r1\n"
        b = "! Last configuration change at 11:30:00 UTC\nhostname r1\n"
        self.assertEqual(device_backup.normalise(a), device_backup.normalise(b))

    def test_redaction_removes_secrets(self):
        red = device_backup.redact("enable secret 9 $9$abc\nsnmp-server community s3cret RO\n")
        self.assertNotIn("$9$abc", red)
        self.assertNotIn("s3cret", red)
