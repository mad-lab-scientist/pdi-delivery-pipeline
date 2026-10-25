#!/usr/bin/env bash
# =============================================================================
# azure-nsg-audit.sh: find Network Security Group rules that expose sensitive ports to the internet,
# across one or all subscriptions. Read-only. Needs the Azure CLI (az), logged in, and jq.
#
#   ./azure-nsg-audit.sh                         current subscription
#   ./azure-nsg-audit.sh --all-subscriptions --format json
#   ./azure-nsg-audit.sh --subscription 00000000-0000-0000-0000-000000000000
#
# Flags inbound Allow rules whose source is Internet / * / 0.0.0.0/0 and whose destination ports
# include 22, 3389, 3306, 5432, 1433, 6379, 27017, 9200 (or * / any range covering them).
# =============================================================================
set -euo pipefail
FORMAT=table ALL_SUBS=0 SUBSCRIPTION=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --all-subscriptions) ALL_SUBS=1; shift ;;
    --subscription) SUBSCRIPTION=$2; shift 2 ;;
    --format) FORMAT=$2; shift 2 ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
command -v az >/dev/null || { echo "the Azure CLI (az) is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "run 'az login' first" >&2; exit 1; }

SENSITIVE='[22,3389,3306,5432,1433,6379,27017,9200,23,11211]'

subscriptions() {
  if [[ -n $SUBSCRIPTION ]]; then echo "$SUBSCRIPTION"
  elif [[ $ALL_SUBS == 1 ]]; then az account list --query "[?state=='Enabled'].id" -o tsv
  else az account show --query id -o tsv; fi
}

findings='[]'
while read -r sub; do
  [[ -z $sub ]] && continue
  name=$(az account show --subscription "$sub" --query name -o tsv 2>/dev/null || echo "$sub")
  nsgs=$(az network nsg list --subscription "$sub" -o json 2>/dev/null || echo '[]')
  sub_findings=$(jq --arg sub "$name" --argjson ports "$SENSITIVE" '
    [ .[] as $nsg | $nsg.securityRules[]?
      | select(.direction == "Inbound" and .access == "Allow")
      | . as $r
      | ((.sourceAddressPrefixes // []) + [.sourceAddressPrefix // ""]) as $srcs
      | select(any($srcs[]; . == "*" or . == "Internet" or . == "0.0.0.0/0" or . == "::/0"))
      | (((.destinationPortRanges // []) + [.destinationPortRange // ""])) as $pr
      | { subscription: $sub, nsg: $nsg.name, rule: .name, priority: .priority,
          source: ($srcs | map(select(. != "")) | join(",")),
          ports: ($pr | map(select(. != "")) | join(",")),
          exposed: [ $ports[] | select(. as $p | $pr | any(
              . == "*" or (. == ($p|tostring)) or
              (test("-") and ((split("-")[0]|tonumber) <= $p) and ((split("-")[1]|tonumber) >= $p)))) ] }
      | select(.exposed | length > 0) ]' <<< "$nsgs")
  findings=$(jq -s 'add' <(echo "$findings") <(echo "$sub_findings"))
done < <(subscriptions)

if [[ $FORMAT == json ]]; then
  echo "$findings"
else
  printf '%-28s %-24s %-22s %-8s %-18s %s\n' SUBSCRIPTION NSG RULE PRIORITY SOURCE EXPOSED_PORTS
  jq -r '.[] | [.subscription, .nsg, .rule, (.priority|tostring), .source, (.exposed|map(tostring)|join(","))] | @tsv' <<< "$findings" \
    | while IFS=$'\t' read -r sub nsg rule prio src ports; do
        printf '%-28.28s %-24.24s %-22.22s %-8s %-18.18s %s\n' "$sub" "$nsg" "$rule" "$prio" "$src" "$ports"
      done
  echo
  echo "$(jq length <<< "$findings") exposed rule(s) found"
fi
[[ $(jq length <<< "$findings") -eq 0 ]]
