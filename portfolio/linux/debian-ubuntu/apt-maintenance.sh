#!/usr/bin/env bash
# =============================================================================
# apt-maintenance.sh: patch a Debian or Ubuntu server and report what it needs.
#
#   sudo ./apt-maintenance.sh --check                 report only: updates, security updates, holds, reboot
#   sudo ./apt-maintenance.sh                         upgrade (keeps held packages), autoremove, clean
#   sudo ./apt-maintenance.sh --security-only         only packages from the -security pocket
#   sudo ./apt-maintenance.sh --full --reboot 5       dist-upgrade, then reboot in 5 minutes if required
#
# Non-interactive and safe for cron/Ansible: keeps existing config files on conflicts
# (--force-confdef/--force-confold) and logs to /var/log/apt-maintenance.log.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

MODE=upgrade REBOOT_MIN="" CHECK=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) CHECK=1; shift ;;
    --security-only) MODE=security; shift ;;
    --full) MODE=full; shift ;;
    --reboot) REBOOT_MIN=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
detect_os
[[ $OS_FAMILY == debian ]] || die "this script is for Debian/Ubuntu (found ${OS_NAME})"
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
LOG=/var/log/apt-maintenance.log
[[ $CHECK == 1 || $DRY_RUN == 1 ]] || exec > >(tee -a "$LOG") 2>&1

step "$(date '+%F %T') ${OS_NAME} on $(uname -n)"
run apt-get update -q
mapfile -t pending < <(apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | awk '/^Inst / {print $2}')
mapfile -t security < <(apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | awk '/^Inst / && /-security/ {print $2}')
held=$(apt-mark showhold | paste -sd' ' -)
info "${#pending[@]} package(s) upgradable, ${#security[@]} from security: ${security[*]:-none}"
[[ -n $held ]] && warn "held packages (not upgraded): ${held}"

if [[ $CHECK == 0 ]]; then
  case $MODE in
    upgrade) run apt-get "${APT_OPTS[@]}" upgrade ;;
    full) run apt-get "${APT_OPTS[@]}" dist-upgrade ;;
    security)
      if (( ${#security[@]} )); then
        run apt-get "${APT_OPTS[@]}" install --only-upgrade "${security[@]}"
      else
        ok "no security updates pending"
      fi ;;
  esac
  run apt-get "${APT_OPTS[@]}" autoremove --purge
  run apt-get -q clean
fi

step "Restart and reboot status"
if command -v needrestart >/dev/null; then
  needrestart -b 2>/dev/null | grep -E '^NEEDRESTART-(KSTA|SVC)' | sed 's/^/  /' || true
fi
if [[ -f /var/run/reboot-required ]]; then
  warn "reboot required by: $(paste -sd' ' - < /var/run/reboot-required.pkgs 2>/dev/null || echo 'a package')"
  if [[ -n $REBOOT_MIN && $CHECK == 0 ]]; then
    [[ $REBOOT_MIN =~ ^[0-9]+$ ]] || die "--reboot takes minutes"
    run shutdown -r "+${REBOOT_MIN}" "apt-maintenance: rebooting to finish updates"
  fi
else
  ok "no reboot required"
fi
