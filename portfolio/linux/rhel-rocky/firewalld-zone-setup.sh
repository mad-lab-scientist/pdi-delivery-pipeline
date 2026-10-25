#!/usr/bin/env bash
# =============================================================================
# firewalld-zone-setup.sh: create or update a firewalld zone for a server role, bound to source
# networks and/or interfaces, with the services and ports that role needs.
#
#   sudo ./firewalld-zone-setup.sh                         interactive
#   sudo ./firewalld-zone-setup.sh --zone web --sources 10.20.0.0/23 --services http,https \
#        --ports 8443/tcp --yes
#   sudo ./firewalld-zone-setup.sh --zone mgmt --sources 10.20.3.0/25 --services ssh,cockpit --dry-run
#
# Permanent configuration only, then a reload; the runtime and permanent configs stay in sync.
# Works on RHEL/Rocky/Alma/Fedora and SUSE (any distro running firewalld).
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ZONE="" SOURCES="" IFACES="" SERVICES="" PORTS="" TARGET=default
while [[ $# -gt 0 ]]; do
  case $1 in
    --zone) ZONE=$2; shift 2 ;;
    --sources) SOURCES=$2; shift 2 ;;
    --interfaces) IFACES=$2; shift 2 ;;
    --services) SERVICES=$2; shift 2 ;;
    --ports) PORTS=$2; shift 2 ;;
    --target) TARGET=$2; shift 2 ;;   # default | ACCEPT | DROP | %%REJECT%%
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '3,13p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
command -v firewall-cmd >/dev/null || die "firewalld is not installed"
[[ $DRY_RUN == 1 ]] || firewall-cmd --state >/dev/null 2>&1 || die "firewalld is not running (systemctl enable --now firewalld)"

is_zone_name() { [[ $1 =~ ^[A-Za-z0-9_-]{1,17}$ ]]; }
is_cidr_list() { local x; for x in ${1//,/ }; do is_cidr "$x" || is_ipv4 "$x" || return 1; done; }
is_service_list() {
  local x known
  known=" $(firewall-cmd --get-services 2>/dev/null || firewall-offline-cmd --get-services 2>/dev/null) "
  for x in ${1//,/ }; do [[ $known == *" $x "* ]] || { warn "unknown firewalld service: $x"; return 1; }; done
}
is_port_list() { local x; for x in ${1//,/ }; do [[ $x =~ ^([0-9]{1,5})(-[0-9]{1,5})?/(tcp|udp|sctp)$ ]] || return 1; done; }

ask ZONE "Zone name (e.g. web, mgmt, db)" "" is_zone_name
ask SOURCES "Source networks, comma separated (blank: none)" "-"
[[ $SOURCES == "-" ]] && SOURCES=""
[[ -z $SOURCES ]] || is_cidr_list "$SOURCES" || die "invalid source list: $SOURCES"
ask SERVICES "Services, comma separated (firewall-cmd --get-services)" "ssh" is_service_list
ask PORTS "Extra ports, e.g. 8443/tcp,9100/tcp (blank: none)" "-"
[[ $PORTS == "-" ]] && PORTS=""
[[ -z $PORTS ]] || is_port_list "$PORTS" || die "invalid port list: $PORTS"
[[ -n $SOURCES || -n $IFACES ]] || die "a zone needs at least one source network or interface to match traffic"

step "Zone ${ZONE}"
printf '  sources    %s\n  interfaces %s\n  services   %s\n  ports      %s\n  target     %s\n' \
  "${SOURCES:-none}" "${IFACES:-none}" "$SERVICES" "${PORTS:-none}" "$TARGET"
confirm "Apply?" || die "aborted"

if ! firewall-cmd --permanent --get-zones 2>/dev/null | tr ' ' '\n' | grep -qx "$ZONE"; then
  run firewall-cmd --permanent --new-zone="$ZONE"
fi
run firewall-cmd --permanent --zone="$ZONE" --set-target="$TARGET"
for s in ${SOURCES//,/ }; do run firewall-cmd --permanent --zone="$ZONE" --add-source="$s"; done
for i in ${IFACES//,/ }; do run firewall-cmd --permanent --zone="$ZONE" --change-interface="$i"; done
for s in ${SERVICES//,/ }; do run firewall-cmd --permanent --zone="$ZONE" --add-service="$s"; done
for p in ${PORTS//,/ }; do run firewall-cmd --permanent --zone="$ZONE" --add-port="$p"; done
run firewall-cmd --reload
[[ $DRY_RUN == 1 ]] || firewall-cmd --zone="$ZONE" --list-all | sed 's/^/  /'
ok "zone ${ZONE} configured"
