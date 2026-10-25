#!/usr/bin/env python3
"""Nutanix inventory through the Prism Central v3 REST API: clusters, hosts and every VM.

    nutanix_inventory.py --pc prism-central.corp.example.com
    NUTANIX_USER=svc-inventory nutanix_inventory.py --pc 10.20.3.50 --format csv > nutanix-vms.csv
    nutanix_inventory.py --pc pc.corp.example.com --ca-bundle /etc/pki/corp-root.pem --format json

Paginates POST /api/nutanix/v3/{clusters,hosts,vms}/list. Credentials come from NUTANIX_USER /
NUTANIX_PASSWORD or a prompt (the password is never echoed or logged). TLS is verified by default; use
--ca-bundle for an internal CA, or --insecure only in a lab. Standard library only.
"""

from __future__ import annotations

import argparse
import base64
import csv
import getpass
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

PAGE = 250


class PrismClient:
    def __init__(self, host: str, user: str, password: str, context: ssl.SSLContext, timeout: float = 30.0) -> None:
        self.base = f"https://{host}:9440/api/nutanix/v3"
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {"Authorization": f"Basic {token}", "Content-Type": "application/json",
                        "Accept": "application/json"}
        self.context = context
        self.timeout = timeout

    def list_all(self, kind: str) -> list[dict]:
        """All entities of a kind (cluster, host, vm), following offset/length pagination."""
        entities: list[dict] = []
        offset = 0
        while True:
            body = json.dumps({"kind": kind, "length": PAGE, "offset": offset}).encode()
            req = urllib.request.Request(f"{self.base}/{kind}s/list", data=body, headers=self.headers, method="POST")
            with urllib.request.urlopen(req, context=self.context, timeout=self.timeout) as resp:  # noqa: S310
                page = json.load(resp)
            batch = page.get("entities", [])
            entities += batch
            total = page.get("metadata", {}).get("total_matches", len(entities))
            offset += len(batch)
            if not batch or offset >= total:
                return entities


def vm_row(vm: dict) -> dict:
    status = vm.get("status", {})
    res = status.get("resources", {})
    disks = [d for d in res.get("disk_list", []) if d.get("device_properties", {}).get("device_type") == "DISK"]
    ips = [ip.get("ip") for nic in res.get("nic_list", []) for ip in nic.get("ip_endpoint_list", []) if ip.get("ip")]
    return {
        "name": status.get("name", ""),
        "cluster": status.get("cluster_reference", {}).get("name", ""),
        "power_state": res.get("power_state", ""),
        "vcpu": res.get("num_sockets", 0) * res.get("num_vcpus_per_socket", 1),
        "memory_gib": round(res.get("memory_size_mib", 0) / 1024, 1),
        "disks": len(disks),
        "disk_gib": round(sum(d.get("disk_size_mib", 0) for d in disks) / 1024, 1),
        "ip_addresses": " ".join(ips),
        "host": res.get("host_reference", {}).get("name", ""),
        "categories": " ".join(f"{k}:{v}" for k, v in vm.get("metadata", {}).get("categories", {}).items()),
        "uuid": vm.get("metadata", {}).get("uuid", ""),
    }


def tls_context(ca_bundle: str | None, insecure: bool) -> ssl.SSLContext:
    if insecure:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    return ssl.create_default_context(cafile=ca_bundle)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pc", required=True, help="Prism Central address (port 9440 is implied)")
    ap.add_argument("--format", choices=["table", "csv", "json"], default="table")
    ap.add_argument("--ca-bundle", help="PEM bundle for an internal CA")
    ap.add_argument("--insecure", action="store_true", help="skip TLS verification (lab only)")
    args = ap.parse_args(argv)
    user = os.environ.get("NUTANIX_USER") or input("Prism user: ").strip()
    password = os.environ.get("NUTANIX_PASSWORD") or getpass.getpass(f"Password for {user}: ")
    client = PrismClient(args.pc, user, password, tls_context(args.ca_bundle, args.insecure))
    try:
        clusters = client.list_all("cluster")
        hosts = client.list_all("host")
        vms = [vm_row(v) for v in client.list_all("vm")]
    except urllib.error.HTTPError as exc:
        print(f"error: Prism returned HTTP {exc.code} ({'check credentials' if exc.code == 401 else exc.reason})",
              file=sys.stderr)
        return 2
    except (urllib.error.URLError, OSError) as exc:
        print(f"error: cannot reach {args.pc}:9440 ({exc})", file=sys.stderr)
        return 2
    vms.sort(key=lambda r: (r["cluster"], r["name"].lower()))
    if args.format == "json":
        print(json.dumps({"clusters": [c.get("status", {}).get("name") for c in clusters],
                          "hosts": len(hosts), "vms": vms}, indent=2))
        return 0
    if args.format == "csv":
        writer = csv.DictWriter(sys.stdout, fieldnames=list(vms[0]) if vms else ["name"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(vms)
        return 0
    for c in clusters:
        st = c.get("status", {})
        res = st.get("resources", {})
        version = res.get("config", {}).get("software_map", {}).get("NOS", {}).get("version", "?")
        nodes = len(res.get("nodes", {}).get("hypervisor_server_list", []))
        print(f"cluster {st.get('name', '?'):<24} AOS {version:<10} {nodes} node(s)")
    print(f"{len(hosts)} host(s)\n")
    print(f"{'VM':<32} {'CLUSTER':<16} {'POWER':<6} {'vCPU':>4} {'MEM GiB':>8} {'DISK GiB':>9}  IP")
    for r in vms:
        print(f"{r['name'][:32]:<32} {r['cluster'][:16]:<16} {r['power_state'][:6]:<6} {r['vcpu']:>4} "
              f"{r['memory_gib']:>8} {r['disk_gib']:>9}  {r['ip_addresses']}")
    on = [r for r in vms if r["power_state"] == "ON"]
    print(f"\n{len(vms)} VM(s), {len(on)} powered on, {sum(r['vcpu'] for r in on)} vCPU and "
          f"{round(sum(r['memory_gib'] for r in on), 1)} GiB in use")
    return 0


if __name__ == "__main__":
    sys.exit(main())
