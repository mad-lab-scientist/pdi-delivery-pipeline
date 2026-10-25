#!/usr/bin/env bash
# =============================================================================
# dnf-maintenance.sh: patch RHEL, Rocky Linux, AlmaLinux, Oracle Linux or Fedora and report status.
#
#   sudo ./dnf-maintenance.sh --check                    updates, security advisories, kernels, reboot
#   sudo ./dnf-maintenance.sh --security-only            apply security errata only (dnf upgrade --security)
#   sudo ./dnf-maintenance.sh --reboot 10                full upgrade; reboot in 10 min if required
#
# Uses dnf's own advisory metadata (updateinfo) so --security-only matches what the vendor marks as
# security errata; reboot detection uses needs-restarting (dnf-utils / dnf-plugins-core).
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
    -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
detect_os
[[ $OS_FAMILY == rhel ]] || die "this script is for the RHEL family (found ${OS_NAME})"
DNF=$(command -v dnf || command -v yum)

step "$(date '+%F %T') ${OS_NAME} on $(uname -n)"
updates=$("$DNF" -q check-update 2>/dev/null | grep -cE '^[[:alnum:]_.+-]+\.[[:alnum:]_]+[[:space:]]' || true)
info "${updates} package update(s) available"
info "security advisories:"
"$DNF" -q updateinfo list --security 2>/dev/null | awk '{print $2}' | sort | uniq -c | sed 's/^/   /' || true
"$DNF" -q updateinfo list --security 2>/dev/null | awk '{print $1}' | sort -u | head -n 15 | sed 's/^/    /' || true

if [[ $CHECK == 0 ]]; then
  if [[ $SECURITY == 1 ]]; then
    run "$DNF" -y upgrade --security
  else
    run "$DNF" -y upgrade
  fi
  run "$DNF" -y autoremove
fi

step "Kernels and reboot"
limit=$(awk -F= '/^installonly_limit/ {gsub(/ /, "", $2); print $2}' /etc/dnf/dnf.conf 2>/dev/null)
info "installed kernels: $(rpm -q kernel-core kernel 2>/dev/null | grep -vc 'not installed') (installonly_limit ${limit:-3}); running $(uname -r)"
if command -v needs-restarting >/dev/null; then
  if needs-restarting -r >/dev/null 2>&1; then
    ok "no reboot required"
  else
    warn "reboot required (core libraries or kernel updated)"
    if [[ -n $REBOOT_MIN && $CHECK == 0 ]]; then
      [[ $REBOOT_MIN =~ ^[0-9]+$ ]] || die "--reboot takes minutes"
      run shutdown -r "+${REBOOT_MIN}" "dnf-maintenance: rebooting to finish updates"
    fi
  fi
  needs-restarting -s 2>/dev/null | sed 's/^/  service to restart: /' || true
else
  warn "needs-restarting not found: install dnf-utils (or dnf-plugins-core) for reboot detection"
fi
step "Recent transactions"
"$DNF" history list 2>/dev/null | head -n 6 | sed 's/^/  /' || true
