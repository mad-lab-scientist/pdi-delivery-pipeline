#!/usr/bin/env bash
# =============================================================================
# pve-vm-inventory.sh: cluster-wide inventory of VMs and containers on Proxmox VE (run on any node).
#
#   ./pve-vm-inventory.sh                  table, sorted by node then VMID
#   ./pve-vm-inventory.sh --csv > guests.csv
#   ./pve-vm-inventory.sh --running        only running guests
#
# Uses the cluster API (pvesh get /cluster/resources), so one run covers every node. Needs jq.
# =============================================================================
set -euo pipefail
FORMAT=table FILTER=all
while [[ $# -gt 0 ]]; do
  case $1 in
    --csv) FORMAT=csv; shift ;;
    --json) FORMAT=json; shift ;;
    --running) FILTER=running; shift ;;
    -h|--help) sed -n '3,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
command -v pvesh >/dev/null || { echo "run this on a Proxmox VE node" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (apt install jq)" >&2; exit 1; }

data=$(pvesh get /cluster/resources --type vm --output-format json | jq --arg f "$FILTER" '
  [ .[] | select($f == "all" or .status == "running") | {
      vmid, name, node, type, status,
      cpus: (.maxcpu // 0),
      mem_gib: (((.maxmem // 0) / 1073741824) * 10 | round / 10),
      mem_used_pct: (if (.maxmem // 0) > 0 then ((.mem // 0) * 100 / .maxmem | round) else 0 end),
      disk_gib: (((.maxdisk // 0) / 1073741824) | round),
      uptime_days: (((.uptime // 0) / 86400) * 10 | round / 10),
      tags: (.tags // ""), pool: (.pool // ""), template: ((.template // 0) == 1)
  } ] | sort_by(.node, .vmid)')

case $FORMAT in
  json) echo "$data" ;;
  csv)
    echo "vmid,name,node,type,status,cpus,mem_gib,mem_used_pct,disk_gib,uptime_days,tags,pool,template"
    jq -r '.[] | [.vmid, .name, .node, .type, .status, .cpus, .mem_gib, .mem_used_pct, .disk_gib, .uptime_days, .tags, .pool, .template] | @csv' <<< "$data" ;;
  table)
    printf '%-6s %-28s %-10s %-5s %-8s %4s %8s %5s %8s %7s  %s\n' VMID NAME NODE TYPE STATUS CPU MEM_GiB MEM% DISK_GiB UP_DAYS TAGS
    jq -r '.[] | [.vmid, (.name + (if .template then " (tpl)" else "" end)), .node, .type, .status, .cpus, .mem_gib, .mem_used_pct, .disk_gib, .uptime_days, .tags] | @tsv' <<< "$data" \
      | while IFS=$'\t' read -r id name node type status cpu mem pct disk up tags; do
          printf '%-6s %-28.28s %-10s %-5s %-8s %4s %8s %4s%% %8s %7s  %s\n' "$id" "$name" "$node" "$type" "$status" "$cpu" "$mem" "$pct" "$disk" "$up" "$tags"
        done
    jq -r '"\n\(length) guest(s): \(map(select(.status == "running")) | length) running, \(map(.cpus) | add // 0) vCPU and \(map(.mem_gib) | add // 0 | . * 10 | round / 10) GiB allocated"' <<< "$data" ;;
esac
