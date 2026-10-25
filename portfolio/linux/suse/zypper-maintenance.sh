#!/usr/bin/env bash
# =============================================================================
# zypper-maintenance.sh: patch SUSE Linux Enterprise / openSUSE with Snapper safety snapshots.
#
#   sudo ./zypper-maintenance.sh --check              pending patches (by category), reboot status
#   sudo ./zypper-maintenance.sh --security-only      install security patches only
#   sudo ./zypper-maintenance.sh                      all patches (Leap/SLES) or dup (Tumbleweed)
#   sudo ./zypper-maintenance.sh --reboot 10          reboot in 10 minutes if required
#
# On Btrfs root with Snapper, a pre/post snapshot pair brackets the change, so a bad update can be
# rolled back with `snapper rollback`.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

CHECK=0 SECURITY=0 REBOOT_MIN=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) CHECK=1; shift ;;
    --security-only) SECURITY=1; shift ;;
    --reboot) REBOOT_MIN=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
detect_os
[[ $OS_FAMILY == suse ]] || die "this script is for SUSE (found ${OS_NAME})"
Z=(zypper --non-interactive)

step "$(date '+%F %T') ${OS_NAME} on $(uname -n)"
run "${Z[@]}" --quiet refresh
info "pending patches by category:"
"${Z[@]}" --quiet list-patches 2>/dev/null | awk -F'|' 'NR > 2 && NF > 4 {gsub(/ /, "", $3); print $3}' \
  | sort | uniq -c | sed 's/^/   /' || true

if [[ $CHECK == 0 ]]; then
  pre=""
  if command -v snapper >/dev/null && snapper list >/dev/null 2>&1; then
    pre=$(run snapper create --type pre --cleanup-algorithm number --print-number --description "zypper-maintenance")
    info "snapper pre-snapshot ${pre}"
  fi
  if [[ $SECURITY == 1 ]]; then
    run "${Z[@]}" patch --category security --auto-agree-with-licenses
  elif [[ $OS_ID == opensuse-tumbleweed ]]; then
    run "${Z[@]}" dup --auto-agree-with-licenses   # rolling release: distribution upgrade is the supported path
  else
    run "${Z[@]}" patch --auto-agree-with-licenses
    run "${Z[@]}" patch --auto-agree-with-licenses   # a second pass applies patches unblocked by zypper's own update
  fi
  if [[ $pre =~ ^[0-9]+$ ]]; then
    run snapper create --type post --pre-number "$pre" --cleanup-algorithm number --description "zypper-maintenance"
  fi
fi

step "Reboot and services"
set +e
"${Z[@]}" needs-rebooting >/dev/null 2>&1
rc=$?
set -e
if [[ $rc == 102 ]]; then
  warn "reboot required"
  if [[ -n $REBOOT_MIN && $CHECK == 0 ]]; then
    [[ $REBOOT_MIN =~ ^[0-9]+$ ]] || die "--reboot takes minutes"
    run shutdown -r "+${REBOOT_MIN}" "zypper-maintenance: rebooting to finish updates"
  fi
else
  ok "no reboot required"
fi
zypper ps -s 2>/dev/null | tail -n +4 | sed 's/^/  /' || true
