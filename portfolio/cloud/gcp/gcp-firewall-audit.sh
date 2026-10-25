#!/usr/bin/env bash
# =============================================================================
# gcp-firewall-audit.sh: find GCP VPC firewall rules that allow sensitive ports from 0.0.0.0/0,
# across one project or all accessible projects. Read-only. Needs gcloud (authenticated) and jq.
#
#   ./gcp-firewall-audit.sh --project my-project
#   ./gcp-firewall-audit.sh --all-projects --format json
#
# Flags ENABLED ingress ALLOW rules whose sourceRanges include 0.0.0.0/0 and which allow tcp/udp on
# 22, 3389, 3306, 5432, 1433, 6379, 27017, 9200 (or 'all', or a range covering them).
# =============================================================================
set -euo pipefail
FORMAT=table ALL_PROJECTS=0 PROJECT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT=$2; shift 2 ;;
    --all-projects) ALL_PROJECTS=1; shift ;;
    --format) FORMAT=$2; shift 2 ;;
    -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
command -v gcloud >/dev/null || { echo "gcloud is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

SENSITIVE='[22,3389,3306,5432,1433,6379,27017,9200,23,11211]'

projects() {
  if [[ -n $PROJECT ]]; then echo "$PROJECT"
  elif [[ $ALL_PROJECTS == 1 ]]; then gcloud projects list --format='value(projectId)'
  else gcloud config get-value project 2>/dev/null; fi
}

findings='[]'
while read -r proj; do
  [[ -z $proj || $proj == "(unset)" ]] && continue
  rules=$(gcloud compute firewall-rules list --project "$proj" --format=json 2>/dev/null || echo '[]')
  proj_findings=$(jq --arg proj "$proj" --argjson ports "$SENSITIVE" '
    [ .[]
      | select((.disabled // false) == false and .direction == "INGRESS")
      | select((.sourceRanges // []) | any(. == "0.0.0.0/0"))
      | . as $r
      | [ .allowed[]? | select(.IPProtocol == "tcp" or .IPProtocol == "udp" or .IPProtocol == "all") ] as $allow
      | { project: $proj, rule: .name, network: (.network | split("/") | last),
          priority: .priority, source: (.sourceRanges | join(",")),
          exposed: [ $ports[] as $p
            | select( $allow | any(
                (.IPProtocol == "all") or
                ((.ports // ["all"]) | any(
                    . == "all" or . == ($p|tostring) or
                    (test("-") and ((split("-")[0]|tonumber) <= $p) and ((split("-")[1]|tonumber) >= $p)))) ) )
            | $p ] }
      | select(.exposed | length > 0) ]' <<< "$rules")
  findings=$(jq -s 'add' <(echo "$findings") <(echo "$proj_findings"))
done < <(projects)

if [[ $FORMAT == json ]]; then
  echo "$findings"
else
  printf '%-24s %-26s %-16s %-8s %-14s %s\n' PROJECT RULE NETWORK PRIORITY SOURCE EXPOSED_PORTS
  jq -r '.[] | [.project, .rule, .network, (.priority|tostring), .source, (.exposed|map(tostring)|join(","))] | @tsv' <<< "$findings" \
    | while IFS=$'\t' read -r proj rule net prio src ports; do
        printf '%-24.24s %-26.26s %-16.16s %-8s %-14.14s %s\n' "$proj" "$rule" "$net" "$prio" "$src" "$ports"
      done
  echo
  echo "$(jq length <<< "$findings") exposed rule(s) found"
fi
[[ $(jq length <<< "$findings") -eq 0 ]]
