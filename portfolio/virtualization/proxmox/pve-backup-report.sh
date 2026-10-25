#!/usr/bin/env bash
# =============================================================================
# pve-backup-report.sh: are all guests actually backed up? (Proxmox VE, run on any cluster node)
#
#   ./pve-backup-report.sh                 newest backup per guest, gaps older than 2 days, failed jobs
#   ./pve-backup-report.sh --max-age 7     flag guests without a backup in the last 7 days
#
# Sources: the backup archives that really exist on every storage with 'backup' content (vzdump files
# and Proxmox Backup Server snapshots, including PBS verification state), guests not covered by any
# backup job (/cluster/backup-info/not-backed-up) and failed vzdump tasks in the window.
# Exit code 1 if any guest is uncovered, has no backup, or its newest backup is older than --max-age.
# =============================================================================
set -euo pipefail
MAX_AGE=2
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-age) MAX_AGE=$2; shift 2 ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
command -v pvesh >/dev/null || { echo "run this on a Proxmox VE node" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[[ $MAX_AGE =~ ^[0-9]+$ ]] || { echo "--max-age takes days" >&2; exit 1; }
now=$(date +%s)
since=$(( now - MAX_AGE * 86400 ))

guests=$(pvesh get /cluster/resources --type vm --output-format json | jq '[.[] | select((.template // 0) == 0) | {vmid, name, node}]')
uncovered=$(pvesh get /cluster/backup-info/not-backed-up --output-format json 2>/dev/null | jq '[.[].vmid]' 2>/dev/null || echo '[]')

# Every backup archive on every backup storage (shared storages are listed once: first node that sees them).
archives='[]'
declare -A seen
for node in $(pvesh get /nodes --output-format json | jq -r '.[] | select(.status == "online") | .node'); do
  for store in $(pvesh get "/nodes/${node}/storage" --content backup --output-format json | jq -r '.[] | select(.active == 1) | "\(.storage):\(.shared // 0)"'); do
    name=${store%%:*}; shared=${store##*:}
    key=$([[ $shared == 1 ]] && echo "$name" || echo "${node}/${name}")
    [[ -n ${seen[$key]:-} ]] && continue
    seen[$key]=1
    list=$(pvesh get "/nodes/${node}/storage/${name}/content" --content backup --output-format json 2>/dev/null \
      | jq --arg s "$key" '[.[] | {vmid, ctime, size, storage: $s, verified: (.verification.state // "")}]' || echo '[]')
    archives=$(jq -s 'add' <(echo "$archives") <(echo "$list"))
  done
done
failed=$(for node in $(pvesh get /nodes --output-format json | jq -r '.[] | select(.status == "online") | .node'); do
  pvesh get "/nodes/${node}/tasks" --typefilter vzdump --since "$since" --errors 1 --output-format json 2>/dev/null \
    | jq -r --arg n "$node" '.[] | "\($n)\t\(.starttime | todate)\t\(.id // "job")\t\(.status)"'
done)

report=$(jq -n --argjson g "$guests" --argjson u "$uncovered" --argjson a "$archives" --argjson now "$now" --argjson max "$MAX_AGE" '
  $g | map(. as $vm |
    ($a | map(select(.vmid == $vm.vmid)) | sort_by(.ctime) | last) as $newest |
    {
      vmid: $vm.vmid, name: $vm.name, node: $vm.node,
      covered: (($u | index($vm.vmid)) == null),
      copies: ($a | map(select(.vmid == $vm.vmid)) | length),
      newest: (if $newest then ($newest.ctime | todate) else "never" end),
      where: (($newest.storage) // "-"),
      verified: (($newest.verified) // ""),
      age_days: (if $newest then (($now - $newest.ctime) / 86400 * 10 | floor / 10) else null end)
    } |
    .problem = (if (.covered | not) then "not in any backup job"
                elif .age_days == null then "no backup found on any storage"
                elif .age_days > $max then "newest backup is \(.age_days) days old"
                elif .verified == "failed" then "PBS verification FAILED"
                else "" end)
  ) | sort_by(.vmid)')

printf '%-6s %-24s %-9s %-4s %6s %-21s %-18s %-9s %s\n' VMID NAME NODE JOB COPIES NEWEST STORAGE VERIFIED PROBLEM
jq -r '.[] | [.vmid, .name, .node, (if .covered then "yes" else "NO" end), .copies, .newest, .where, (if .verified == "" then "-" else .verified end), .problem] | @tsv' <<< "$report" \
  | while IFS=$'\t' read -r id name node job copies newest where ver problem; do
      printf '%-6s %-24.24s %-9s %-4s %6s %-21s %-18.18s %-9s %s\n' "$id" "$name" "$node" "$job" "$copies" "$newest" "$where" "$ver" "$problem"
    done
if [[ -n $failed ]]; then
  echo -e "\nFailed vzdump tasks in the last ${MAX_AGE} day(s):"
  printf '  %s\n' "$failed"
fi
bad=$(jq '[.[] | select(.problem != "")] | length' <<< "$report")
echo -e "\n$(jq length <<< "$report") guest(s), $(jq length <<< "$archives") archive(s), ${bad} guest(s) with a backup problem"
[[ $bad == 0 ]]
