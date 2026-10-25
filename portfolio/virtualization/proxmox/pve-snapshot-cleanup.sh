#!/usr/bin/env bash
# =============================================================================
# pve-snapshot-cleanup.sh: find (and optionally delete) old VM/CT snapshots across a Proxmox cluster.
# Forgotten snapshots grow without limit and slow storage; this lists every snapshot with its age.
#
#   ./pve-snapshot-cleanup.sh                     list all snapshots older than 14 days
#   ./pve-snapshot-cleanup.sh --days 30 --delete  delete them (asks once; --yes for cron)
#   ./pve-snapshot-cleanup.sh --keep-pattern '^(pre-upgrade|golden)'   never delete matching names
# =============================================================================
set -euo pipefail
DAYS=14 DELETE=0 YES=0 KEEP=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --days) DAYS=$2; shift 2 ;;
    --delete) DELETE=1; shift ;;
    --keep-pattern) KEEP=$2; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    -h|--help) sed -n '3,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
command -v pvesh >/dev/null || { echo "run this on a Proxmox VE node" >&2; exit 1; }
[[ $DAYS =~ ^[0-9]+$ ]] || { echo "--days takes a number" >&2; exit 1; }
cutoff=$(( $(date +%s) - DAYS * 86400 ))

mapfile -t old < <(
  pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | select((.template // 0) == 0) | "\(.node) \(.type) \(.vmid) \(.name)"' |
  while read -r node type vmid name; do
    pvesh get "/nodes/${node}/${type}/${vmid}/snapshot" --output-format json 2>/dev/null |
      jq -r --arg n "$node" --arg t "$type" --arg v "$vmid" --arg vm "$name" --argjson c "$cutoff" \
        '.[] | select(.name != "current" and (.snaptime // 0) < $c) | "\($n)\t\($t)\t\($v)\t\($vm)\t\(.name)\t\(.snaptime)"'
  done)

printf '%-10s %-5s %-6s %-24s %-28s %s\n' NODE TYPE VMID GUEST SNAPSHOT AGE_DAYS
targets=()
for line in "${old[@]}"; do
  IFS=$'\t' read -r node type vmid guest snap time <<< "$line"
  age=$(( ($(date +%s) - time) / 86400 ))
  keep=""
  [[ -n $KEEP && $snap =~ $KEEP ]] && keep="  (kept: matches --keep-pattern)"
  printf '%-10s %-5s %-6s %-24.24s %-28.28s %s%s\n' "$node" "$type" "$vmid" "$guest" "$snap" "$age" "$keep"
  [[ -z $keep ]] && targets+=("$line")
done
echo -e "\n${#old[@]} snapshot(s) older than ${DAYS} days, ${#targets[@]} eligible for deletion"

if [[ $DELETE == 1 && ${#targets[@]} -gt 0 ]]; then
  if [[ $YES == 0 ]]; then read -r -p "Delete ${#targets[@]} snapshot(s)? [y/N] " a; [[ $a =~ ^[Yy]$ ]] || exit 0; fi
  for line in "${targets[@]}"; do
    IFS=$'\t' read -r node type vmid _ snap _ <<< "$line"
    echo "deleting ${type}/${vmid}@${snap} on ${node}"
    pvesh delete "/nodes/${node}/${type}/${vmid}/snapshot/${snap}" >/dev/null
  done
fi
