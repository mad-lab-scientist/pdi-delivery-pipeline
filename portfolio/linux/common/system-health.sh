#!/usr/bin/env bash
# =============================================================================
# system-health.sh: one-screen health check for any Linux server (Debian/Ubuntu, RHEL/Rocky/Alma,
# SUSE, Alpine, Arch). Read-only; safe to run from cron or a monitoring agent.
#
#   ./system-health.sh                      full report
#   ./system-health.sh --quiet              print only problems (cron: mail on output)
#   ./system-health.sh --disk-warn 80 --disk-crit 90 --mem-warn 90
#
# Exit codes: 0 OK, 1 WARNING, 2 CRITICAL (Nagios convention).
# =============================================================================
set -uo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

DISK_WARN=80 DISK_CRIT=90 MEM_WARN=90 LOAD_FACTOR=2 QUIET=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --disk-warn) DISK_WARN=$2; shift 2 ;;
    --disk-crit) DISK_CRIT=$2; shift 2 ;;
    --mem-warn) MEM_WARN=$2; shift 2 ;;
    --load-factor) LOAD_FACTOR=$2; shift 2 ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

STATUS=0
PROBLEMS=()
flag() { # flag LEVEL MESSAGE   (1 = warning, 2 = critical)
  (( $1 > STATUS )) && STATUS=$1
  PROBLEMS+=("$([[ $1 == 2 ]] && echo CRITICAL || echo WARNING): $2")
}
say() { [[ $QUIET == 1 ]] || printf '%s\n' "$*"; }

detect_os
up_secs=$(cut -d. -f1 /proc/uptime)
up_text="$(( up_secs / 86400 ))d $(( up_secs % 86400 / 3600 ))h $(( up_secs % 3600 / 60 ))m"
say "$(uname -n) | ${OS_NAME} | kernel $(uname -r) | up ${up_text}"

# ---- CPU load
cores=$(nproc)
read -r load1 load5 load15 _ < /proc/loadavg
say "load    ${load1} ${load5} ${load15} on ${cores} core(s)"
if awk -v l="$load5" -v c="$cores" -v f="$LOAD_FACTOR" 'BEGIN { exit !(l > c * f) }'; then
  flag 1 "5-minute load ${load5} is above ${LOAD_FACTOR}x the ${cores} core(s)"
fi

# ---- memory (MemAvailable accounts for reclaimable cache)
mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
mem_used_pct=$(( 100 - mem_avail * 100 / mem_total ))
say "memory  ${mem_used_pct}% used of $(( mem_total / 1024 )) MiB; swap $(( (swap_total - swap_free) / 1024 )) of $(( swap_total / 1024 )) MiB used"
(( mem_used_pct >= MEM_WARN )) && flag 1 "memory ${mem_used_pct}% used"

# ---- filesystems (local only) and inodes
say "disks"
filesystems() {
  local skip=(-x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs)
  if df -P --output=target >/dev/null 2>&1; then   # GNU coreutils
    df -P --output=target,pcent,ipcent,fstype "${skip[@]}" 2>/dev/null | tail -n +2 \
      | awk '{print $1, $2, ($3 == "-" ? "0%" : $3), $4}'
  else                                              # BusyBox (Alpine): no --output, no inode column
    df -P 2>/dev/null | tail -n +2 | awk '$1 !~ /^(tmpfs|devtmpfs|overlay|shm)$/ {print $6, $5, "0%", $1}'
  fi
}
while read -r target pcent ipcent fstype; do
  used=${pcent%\%}; iused=${ipcent%\%}
  say "        $(printf '%-28s %4s used  %4s inodes  %s' "$target" "$pcent" "$ipcent" "$fstype")"
  if (( used >= DISK_CRIT )); then flag 2 "$target is ${used}% full"
  elif (( used >= DISK_WARN )); then flag 1 "$target is ${used}% full"; fi
  [[ $iused =~ ^[0-9]+$ ]] && (( iused >= DISK_CRIT )) && flag 2 "$target inodes ${iused}% used"
done < <(filesystems)

# ---- systemd units
if has_systemd; then
  mapfile -t failed < <(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
  say "units   ${#failed[@]} failed${failed:+: ${failed[*]}}"
  (( ${#failed[@]} > 0 )) && flag 2 "failed systemd units: ${failed[*]}"
  if command -v timedatectl >/dev/null; then
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)
    say "time    NTP synchronized: ${synced}"
    [[ $synced == no ]] && flag 1 "clock is not NTP-synchronized"
  fi
fi

# ---- pending updates and reboot
updates="?"
case $PKG in
  apt) updates=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ') ;;
  dnf|yum) updates=$("$PKG" -q check-update 2>/dev/null | grep -cE '^[[:alnum:]_.+-]+\.[[:alnum:]_]+[[:space:]]') ;;
  zypper) updates=$(zypper --non-interactive --quiet list-updates 2>/dev/null | grep -c '^v ') ;;
  apk) updates=$(apk version -l '<' 2>/dev/null | tail -n +2 | wc -l) ;;
esac
say "updates ${updates} package update(s) available"
reboot_required() {
  [[ -f /var/run/reboot-required ]] && return 0                       # Debian/Ubuntu
  if command -v needs-restarting >/dev/null; then                     # RHEL family (dnf-utils)
    needs-restarting -r >/dev/null 2>&1 && return 1 || return 0
  fi
  if [[ $PKG == zypper ]]; then                                        # SUSE: exit 102 = reboot needed
    zypper needs-rebooting >/dev/null 2>&1
    [[ $? -eq 102 ]] && return 0
  fi
  return 1
}
reboot_needed=no
reboot_required && reboot_needed=yes
say "reboot  required: ${reboot_needed}"
[[ $reboot_needed == yes ]] && flag 1 "a reboot is pending (kernel or core library update)"

# ---- top processes and listening sockets
if [[ $QUIET == 0 ]]; then
  say "top cpu"
  ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | sed -n '2,6p' | sed 's/^/        /'
  if command -v ss >/dev/null; then
    say "listening"
    ss -Htlnp 2>/dev/null | awk '{split($6, p, "\""); printf "        %-24s %s\n", $4, p[2]}' | sort -u | head -n 15
  fi
fi

if (( ${#PROBLEMS[@]} )); then
  [[ $QUIET == 1 ]] && printf '%s\n' "$(uname -n): $([[ $STATUS == 2 ]] && echo CRITICAL || echo WARNING)"
  printf '  - %s\n' "${PROBLEMS[@]}"
else
  say "OK: no problems found"
fi
exit "$STATUS"
