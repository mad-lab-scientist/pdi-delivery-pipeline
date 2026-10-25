#!/usr/bin/env bash
# =============================================================================
# configure-static-ip.sh: set a static IPv4 address, gateway, DNS servers and search domain on any
# mainstream distribution, with an automatic rollback if you lose connectivity.
#
#   sudo ./configure-static-ip.sh                       interactive: lists interfaces, prompts for values
#   sudo ./configure-static-ip.sh --interface ens18 --address 10.20.3.10/25 --gateway 10.20.3.1 \
#        --dns 10.20.3.21,10.20.3.22 --search corp.example --yes
#   sudo ./configure-static-ip.sh --dry-run ...         print the generated configuration only
#
# Backends (auto-detected, or --backend): netplan (Ubuntu), NetworkManager/nmcli (RHEL, Rocky, Alma,
# Fedora, SLES 16), ifupdown (Debian), wicked (SLES 15 / openSUSE Leap).
# Safety: the current configuration is backed up to /var/backups/static-ip/<time>/ and a rollback is
# scheduled BEFORE the change. Confirm within --rollback seconds (default 120) to keep the new
# settings; if your SSH session drops, the old configuration comes back on its own. With --yes the
# change is kept only if the gateway answers ping.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

IFACE="" ADDRESS="" GATEWAY="" DNS="" SEARCH="" MTU="" BACKEND=auto ROLLBACK=120 SEARCH_SET=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --interface) IFACE=$2; shift 2 ;;
    --address) ADDRESS=$2; shift 2 ;;
    --gateway) GATEWAY=$2; shift 2 ;;
    --dns) DNS=$2; shift 2 ;;
    --search) SEARCH=$2; SEARCH_SET=1; shift 2 ;;
    --mtu) MTU=$2; shift 2 ;;
    --backend) BACKEND=$2; shift 2 ;;
    --rollback) ROLLBACK=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
[[ $DRY_RUN == 1 ]] || require_root
detect_os
command -v ip >/dev/null || die "the 'ip' command (iproute2) is required"

# ---------------------------------------------------------------- validators
is_iface() { [[ -e "/sys/class/net/$1" && $1 != lo ]]; }
is_host_cidr() {
  is_cidr "$1" || return 1
  local ip=${1%/*} prefix=${1#*/} n
  (( prefix >= 8 )) || return 1
  (( prefix >= 31 )) && return 0
  n=$(ip_to_int "$ip")
  local mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  local net=$(( n & mask )) bcast=$(( (n | ~mask) & 0xFFFFFFFF ))
  (( n != net && n != bcast ))   # a host address: not the network or broadcast address
}
is_gateway() { is_ipv4 "$1" && [[ $1 != "${ADDRESS%/*}" ]] && same_subnet "$1" "${ADDRESS%/*}" "${ADDRESS#*/}"; }
is_ipv4_list() { local x; IFS=', ' read -r -a _l <<< "$1"; (( ${#_l[@]} )) || return 1; for x in "${_l[@]}"; do is_ipv4 "$x" || return 1; done; }
is_domain_list() { local x; IFS=', ' read -r -a _l <<< "$1"; for x in "${_l[@]}"; do is_fqdn "$x" || return 1; done; }

# ---------------------------------------------------------------- gather values
step "Interfaces"
ip -br -4 addr show 2>/dev/null | grep -vE '^(lo|docker|br-|veth|virbr)' | sed 's/^/  /' || true
default_if=$(ip -4 route show default 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="dev") {print $(i+1); exit}}')
ask IFACE "Interface to configure" "${default_if:-}" is_iface
current_addr=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4; exit}')
current_gw=$(ip -4 route show default dev "$IFACE" 2>/dev/null | awk '{print $3; exit}')
current_dns=$(awk '/^nameserver/ && $2 !~ /^127\./ {printf "%s%s", sep, $2; sep=","}' /etc/resolv.conf 2>/dev/null || true)
ask ADDRESS "IPv4 address/prefix (e.g. 10.20.3.10/25)" "${current_addr:-}" is_host_cidr
ask GATEWAY "Default gateway" "${current_gw:-}" is_gateway
ask DNS "DNS servers (comma separated)" "${current_dns:-}" is_ipv4_list
if [[ $SEARCH_SET == 0 && $ASSUME_YES == 0 && -t 0 ]]; then
  read -r -p "DNS search domain(s) (comma separated, blank for none): " SEARCH
fi
[[ -z "$SEARCH" ]] || is_domain_list "$SEARCH" || die "invalid search domain list: $SEARCH"
[[ -z "$MTU" ]] || [[ $MTU =~ ^[0-9]+$ && $MTU -ge 576 && $MTU -le 9216 ]] || die "MTU must be 576-9216"
[[ $ROLLBACK =~ ^[0-9]+$ && $ROLLBACK -ge 30 ]] || die "--rollback must be at least 30 seconds"
DNS_LIST=${DNS//,/ }; SEARCH_LIST=${SEARCH//,/ }

if [[ $BACKEND == auto ]]; then
  if command -v netplan >/dev/null && [[ -d /etc/netplan ]]; then BACKEND=netplan
  elif command -v nmcli >/dev/null && nmcli -t -f RUNNING general 2>/dev/null | grep -qx running; then BACKEND="nm"
  elif command -v wicked >/dev/null && systemctl is-active --quiet wicked 2>/dev/null; then BACKEND=wicked
  elif [[ -f /etc/network/interfaces ]]; then BACKEND=ifupdown
  else die "no supported network backend found (netplan, NetworkManager, wicked, ifupdown); use --backend"; fi
fi
[[ $BACKEND =~ ^(netplan|nm|ifupdown|wicked)$ ]] || die "unknown backend: $BACKEND"

step "Plan (${BACKEND} on ${OS_NAME})"
printf '  interface %s\n  address   %s (mask %s)\n  gateway   %s\n  dns       %s\n  search    %s\n' \
  "$IFACE" "$ADDRESS" "$(prefix_to_mask "${ADDRESS#*/}")" "$GATEWAY" "$DNS_LIST" "${SEARCH_LIST:-(none)}"
[[ -z "$MTU" ]] || printf '  mtu       %s\n' "$MTU"
[[ $DRY_RUN == 1 ]] || confirm "Apply this configuration?" || die "aborted"

TS=$(date +%Y%m%d-%H%M%S)
BACKUP=/var/backups/static-ip/$TS
yaml_list() { local out="" x; for x in "$@"; do out+="${out:+, }$x"; done; printf '[%s]' "$out"; }
# lines LINE...: print the non-empty arguments, one per line (optional settings simply pass "")
lines() { local l; for l in "$@"; do [[ -n "$l" ]] && printf '%s\n' "$l"; done; return 0; }
# shellcheck disable=SC2086  # DNS_LIST / SEARCH_LIST are space-separated lists, split on purpose below

# ---------------------------------------------------------------- per-backend configuration
case $BACKEND in
  netplan)
    BACKUP_PATHS=(/etc/netplan /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg)
    APPLY="netplan apply"
    [[ -d "/sys/class/net/$IFACE/bonding" || -d "/sys/class/net/$IFACE/bridge" || -e "/proc/net/vlan/$IFACE" ]] \
      && die "$IFACE is a bond/bridge/VLAN: edit its netplan definition directly"
    if grep -lsE "^[[:space:]]+${IFACE}:" /etc/netplan/*.yaml 2>/dev/null | xargs -r grep -lsE '^[[:space:]]+addresses:' >/dev/null; then
      warn "another netplan file already lists addresses for ${IFACE}; review /etc/netplan after applying"
    fi
    write_netplan() {
      lines "# Managed by configure-static-ip.sh ($TS)" "network:" "  version: 2" "  ethernets:" "    ${IFACE}:" \
        "      dhcp4: false" "      dhcp6: false" "      addresses: [${ADDRESS}]" \
        "${MTU:+      mtu: ${MTU}}" "      routes:" "        - to: default" "          via: ${GATEWAY}" \
        "      nameservers:" "        addresses: $(yaml_list $DNS_LIST)" \
        "${SEARCH_LIST:+        search: $(yaml_list $SEARCH_LIST)}" \
        | write_file "/etc/netplan/90-static-${IFACE}.yaml" 0600
      if [[ -d /etc/cloud ]]; then   # stop cloud-init from regenerating DHCP config on reboot
        echo "network: {config: disabled}" | write_file /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
      fi
      [[ $DRY_RUN == 1 ]] || netplan generate || die "netplan rejected the configuration"
    }
    CONFIGURE=write_netplan ;;
  nm)
    BACKUP_PATHS=(/etc/NetworkManager/system-connections /etc/sysconfig/network-scripts)
    con=$(nmcli -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true)
    configure_nm() {
      if [[ -z "$con" || "$con" == "--" ]]; then
        con="static-${IFACE}"
        run nmcli connection add type ethernet ifname "$IFACE" con-name "$con"
      fi
      run nmcli connection modify "$con" ipv4.method manual ipv4.addresses "$ADDRESS" ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS_LIST" ipv4.dns-search "$SEARCH_LIST" ipv4.ignore-auto-dns yes connection.autoconnect yes
      [[ -z "$MTU" ]] || run nmcli connection modify "$con" 802-3-ethernet.mtu "$MTU"
      APPLY="nmcli connection up '${con}'"
    }
    APPLY="nmcli connection up '${con:-static-$IFACE}'"
    CONFIGURE=configure_nm ;;
  ifupdown)
    BACKUP_PATHS=(/etc/network/interfaces /etc/network/interfaces.d /etc/resolv.conf /etc/systemd/resolved.conf.d)
    APPLY="ifdown --force ${IFACE}; ifup ${IFACE}"
    configure_ifupdown() {
      # Comment out the interface's existing stanza and auto/allow-hotplug entries, keep everything else.
      awk -v ifc="$IFACE" '
        /^[[:space:]]*(auto|allow-hotplug|allow-auto)[[:space:]]/ {
          line = $1; n = 0
          for (i = 2; i <= NF; i++) if ($i != ifc) { line = line " " $i; n++ }
          if (n == NF - 1) { print; next }
          print "# " $0 "   # moved to interfaces.d/" ifc
          if (n) print line
          next }
        /^[[:space:]]*(iface|mapping|source|source-directory)[[:space:]]/ { inst = ($1 == "iface" && $2 == ifc && $3 == "inet") }
        { print (inst ? "# " $0 : $0) }' /etc/network/interfaces > /tmp/interfaces.new
      if ! grep -qE '^[[:space:]]*source(-directory)?[[:space:]]+/etc/network/interfaces\.d' /tmp/interfaces.new; then
        echo "source /etc/network/interfaces.d/*" >> /tmp/interfaces.new
      fi
      write_file /etc/network/interfaces < /tmp/interfaces.new
      lines "# Managed by configure-static-ip.sh ($TS)" "auto ${IFACE}" "iface ${IFACE} inet static" \
        "    address ${ADDRESS}" "    gateway ${GATEWAY}" "    dns-nameservers ${DNS_LIST}" \
        "${SEARCH_LIST:+    dns-search ${SEARCH_LIST}}" "${MTU:+    mtu ${MTU}}" \
        | write_file "/etc/network/interfaces.d/${IFACE}"
      if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        printf '[Resolve]\nDNS=%s\nDomains=%s\n' "$DNS_LIST" "$SEARCH_LIST" | write_file /etc/systemd/resolved.conf.d/static-ip.conf
        APPLY+="; systemctl restart systemd-resolved"
      elif ! command -v resolvconf >/dev/null; then
        { [[ -n "$SEARCH_LIST" ]] && echo "search ${SEARCH_LIST}"; for s in $DNS_LIST; do echo "nameserver $s"; done; } \
          | write_file /etc/resolv.conf
      fi
    }
    CONFIGURE=configure_ifupdown ;;
  wicked)
    BACKUP_PATHS=(/etc/sysconfig/network)
    APPLY="netconfig update -f; wicked ifreload ${IFACE}"
    configure_wicked() {
      local mtu_line=""
      [[ -z "$MTU" ]] || mtu_line="MTU='${MTU}'"
      lines "# Managed by configure-static-ip.sh ($TS)" "BOOTPROTO='static'" "STARTMODE='auto'" \
        "IPADDR='${ADDRESS}'" "$mtu_line" | write_file "/etc/sysconfig/network/ifcfg-${IFACE}"
      echo "default ${GATEWAY} - ${IFACE}" | write_file "/etc/sysconfig/network/ifroute-${IFACE}"
      local netconfig=/etc/sysconfig/network/config
      {
        if [[ -f $netconfig ]]; then
          grep -vE '^NETCONFIG_DNS_STATIC_(SERVERS|SEARCHLIST)=' "$netconfig" || true
        fi
        echo "NETCONFIG_DNS_STATIC_SERVERS=\"${DNS_LIST}\""
        echo "NETCONFIG_DNS_STATIC_SEARCHLIST=\"${SEARCH_LIST}\""
      } | write_file "$netconfig"
    }
    CONFIGURE=configure_wicked ;;
esac

# ---------------------------------------------------------------- backup, schedule rollback, apply
if [[ $DRY_RUN == 1 ]]; then
  $CONFIGURE
  info "[dry-run] would back up ${BACKUP_PATHS[*]} to ${BACKUP}, schedule a ${ROLLBACK}s rollback, then run: ${APPLY}"
  exit 0
fi

mkdir -p "$BACKUP"
ABSENT=()
for p in "${BACKUP_PATHS[@]}"; do
  if [[ -e $p ]]; then cp -a --parents "$p" "$BACKUP/"; else ABSENT+=("$p"); fi
done
$CONFIGURE
{
  echo "#!/bin/bash"
  echo "# Restores the network configuration saved at $TS and re-applies it."
  for p in "${BACKUP_PATHS[@]}"; do
    if [[ -e "$BACKUP$p" ]]; then printf 'rm -rf %q && cp -a %q %q\n' "$p" "$BACKUP$p" "$p"; fi
  done
  for p in "${ABSENT[@]}"; do printf 'rm -rf %q\n' "$p"; done   # created by this change
  [[ $BACKEND == nm ]] && echo "nmcli connection reload"
  echo "$APPLY"
  echo "logger -t configure-static-ip 'rolled back network configuration to $TS'"
} > "$BACKUP/rollback.sh"
chmod 0700 "$BACKUP/rollback.sh"

UNIT="static-ip-rollback-$TS"
if has_systemd; then
  systemd-run --quiet --unit "$UNIT" --on-active="${ROLLBACK}s" /bin/bash "$BACKUP/rollback.sh"
  cancel_rollback() { systemctl stop "${UNIT}.timer" 2>/dev/null || true; }
else
  nohup bash -c "sleep ${ROLLBACK}; bash '$BACKUP/rollback.sh'" >/dev/null 2>&1 &
  rb_pid=$!
  cancel_rollback() { kill "$rb_pid" 2>/dev/null || true; }
fi
info "rollback scheduled in ${ROLLBACK}s (backup: ${BACKUP})"

step "Applying"
nohup bash -c "$APPLY" >/dev/null 2>&1 &
sleep 8
reachable=no
ping -c 3 -W 2 "$GATEWAY" >/dev/null 2>&1 && reachable=yes
info "gateway ${GATEWAY} reachable: ${reachable}"
ip -br -4 addr show dev "$IFACE" | sed 's/^/  /'

if [[ $ASSUME_YES == 1 ]]; then
  if [[ $reachable == yes ]]; then cancel_rollback; ok "kept (gateway answered)"; exit 0; fi
  warn "gateway did not answer: rolling back now"; cancel_rollback; bash "$BACKUP/rollback.sh"; exit 1
fi
if read -r -t $(( ROLLBACK - 15 )) -p "Type 'keep' within $(( ROLLBACK - 15 ))s to keep the new settings: " answer \
   && [[ $answer == keep ]]; then
  cancel_rollback
  ok "new configuration kept; backup remains in ${BACKUP}"
else
  echo
  warn "not confirmed: the previous configuration will be restored automatically"
fi
