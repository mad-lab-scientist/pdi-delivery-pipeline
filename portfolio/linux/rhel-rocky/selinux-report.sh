#!/usr/bin/env bash
# =============================================================================
# selinux-report.sh: explain recent SELinux denials and suggest the right fix, instead of setenforce 0.
#
#   sudo ./selinux-report.sh                     denials from the last 24 hours
#   sudo ./selinux-report.sh --since recent      last 10 minutes (ausearch keywords: recent, today, boot...)
#
# Groups AVC denials by process, permission and target type, runs audit2why to classify each
# (missing boolean, wrong file context, or a real policy gap), and lists custom booleans and
# file-context rules already present. Read-only. Needs audit + policycoreutils-python-utils.
# =============================================================================
set -uo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

SINCE="yesterday"
while [[ $# -gt 0 ]]; do
  case $1 in
    --since) SINCE=$2; shift 2 ;;
    -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
command -v getenforce >/dev/null || die "SELinux tools not found"

step "Status"
sestatus 2>/dev/null | grep -E 'status|mode|policy name' | sed 's/^/  /'
[[ $(getenforce) == Disabled ]] && { warn "SELinux is disabled; enabling needs a relabel and reboot"; exit 1; }

step "Denials since ${SINCE}"
events=$(ausearch -m AVC,USER_AVC -ts "$SINCE" 2>/dev/null)
if [[ -z $events ]]; then ok "no AVC denials"; else
  grep -oE 'avc:  denied  \{ [^}]+\} .* comm="[^"]+".* tcontext=[^ ]+ tclass=[^ ]+' <<< "$events" \
    | sed -E 's/avc:  denied  \{ ([^}]+) \}.*comm="([^"]+)".*tcontext=[^:]+:[^:]+:([^:]+):[^ ]+ tclass=([^ ]+)/\2 -> \1 on \3 (\4)/' \
    | sort | uniq -c | sort -rn | head -n 20 | sed 's/^/  /'
  step "Why (audit2why)"
  if command -v audit2why >/dev/null; then
    audit2why <<< "$events" 2>/dev/null | grep -E 'Was caused by|setsebool|restorecon|semanage|Missing type enforcement' \
      | sort | uniq -c | sort -rn | sed 's/^/  /'
  else
    warn "audit2why not found (dnf install policycoreutils-python-utils)"
  fi
  step "Typical fixes"
  cat <<'EOF'
  boolean:      setsebool -P <boolean> on                       (audit2why names it)
  file context: semanage fcontext -a -t <type> '/srv/app(/.*)?' && restorecon -Rv /srv/app
  port:         semanage port -a -t http_port_t -p tcp 8443
  policy gap:   ausearch -m AVC -ts recent | audit2allow -M local_fix  (review the .te file before semodule -i)
EOF
fi

step "Local customisations"
semanage boolean -l -C 2>/dev/null | tail -n +2 | sed 's/^/  boolean: /' || true
semanage fcontext -l -C 2>/dev/null | tail -n +2 | sed 's/^/  fcontext: /' || true
semanage port -l -C 2>/dev/null | tail -n +2 | sed 's/^/  port: /' || true
