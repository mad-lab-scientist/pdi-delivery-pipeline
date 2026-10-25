#!/usr/bin/env bash
# =============================================================================
# pve-clone-vm.sh: deploy a VM from a cloud-init template with a static IP, gateway, DNS and search
# domain, sized CPU/RAM/disk, then start it and wait for the guest agent to report its address.
#
#   ./pve-clone-vm.sh                                    interactive (suggests the next free VMID)
#   ./pve-clone-vm.sh --template 9000 --name app01 --cores 4 --memory 8192 --disk 60 \
#       --ip 10.20.3.40/25 --gateway 10.20.3.1 --dns 10.20.3.21,10.20.3.22 --domain corp.example.com --yes
#
# Full clone (independent of the template), optional VLAN override, optional target node for clusters.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../../linux/lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../../linux/lib/common.sh"

TEMPLATE="" VMID="" NAME="" CORES="" MEMORY="" DISK="" IP="" GATEWAY="" DNS="" DOMAIN="" VLAN="" STORAGE="" TARGET_NODE="" START=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --template) TEMPLATE=$2; shift 2 ;;
    --vmid) VMID=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --cores) CORES=$2; shift 2 ;;
    --memory) MEMORY=$2; shift 2 ;;
    --disk) DISK=$2; shift 2 ;;
    --ip) IP=$2; shift 2 ;;
    --gateway) GATEWAY=$2; shift 2 ;;
    --dns) DNS=$2; shift 2 ;;
    --domain) DOMAIN=$2; shift 2 ;;
    --vlan) VLAN=$2; shift 2 ;;
    --storage) STORAGE=$2; shift 2 ;;
    --node) TARGET_NODE=$2; shift 2 ;;
    --no-start) START=0; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
command -v qm >/dev/null || die "run this on a Proxmox VE node"

is_template() { qm config "$1" 2>/dev/null | grep -q '^template: 1'; }
is_free_vmid() { [[ $1 =~ ^[0-9]{3,9}$ ]] && ! qm status "$1" >/dev/null 2>&1; }
is_int_range() { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= $2 && $1 <= $3 )); }
is_cores() { is_int_range "$1" 1 128; }
is_mem() { is_int_range "$1" 512 1048576; }
is_disk() { is_int_range "$1" 8 65536; }
is_host_cidr() { is_cidr "$1" && (( ${1#*/} >= 8 && ${1#*/} <= 30 )); }
is_gw() { is_ipv4 "$1" && same_subnet "$1" "${IP%/*}" "${IP#*/}" && [[ $1 != "${IP%/*}" ]]; }
is_dns_list() { local x; for x in ${1//,/ }; do is_ipv4 "$x" || return 1; done; }

info "templates: $(qm list | awk 'NR > 1 {print $1}' | while read -r id; do is_template "$id" && printf '%s(%s) ' "$id" "$(qm config "$id" | awk '/^name:/ {print $2}')"; done)"
ask TEMPLATE "Template VMID" "9000" is_template
ask VMID "New VMID" "$(pvesh get /cluster/nextid)" is_free_vmid
ask NAME "VM name / hostname" "" is_hostname
ask CORES "vCPU cores" "2" is_cores
ask MEMORY "Memory (MiB)" "4096" is_mem
ask DISK "System disk size (GiB, grows the template disk)" "32" is_disk
ask IP "IPv4 address/prefix (e.g. 10.20.3.40/25)" "" is_host_cidr
ask GATEWAY "Default gateway" "" is_gw
ask DNS "DNS servers (comma separated)" "" is_dns_list
ask DOMAIN "DNS search domain" "" is_fqdn

step "Clone ${TEMPLATE} -> ${VMID} (${NAME})"
printf '  %s vCPU, %s MiB, %s GiB disk, %s via %s, DNS %s, domain %s\n' "$CORES" "$MEMORY" "$DISK" "$IP" "$GATEWAY" "$DNS" "$DOMAIN"
confirm "Create and $([[ $START == 1 ]] && echo start || echo leave stopped)?" || die "aborted"
clone=(qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full 1)
[[ -n $STORAGE ]] && clone+=(--storage "$STORAGE")
[[ -n $TARGET_NODE ]] && clone+=(--target "$TARGET_NODE")
"${clone[@]}"
qm set "$VMID" --cores "$CORES" --memory "$MEMORY" --ipconfig0 "ip=${IP},gw=${GATEWAY}" \
  --nameserver "${DNS//,/ }" --searchdomain "$DOMAIN"
if [[ -n $VLAN ]]; then
  net=$(qm config "$VMID" | awk -F': ' '/^net0:/ {print $2}' | sed -E 's/,tag=[0-9]+//')
  qm set "$VMID" --net0 "${net},tag=${VLAN}"
fi
current=$(qm config "$VMID" | awk -F'size=' '/^scsi0:/ {split($2, a, ","); print a[1]}' | tr -d 'G')
if [[ $current =~ ^[0-9]+$ ]] && (( DISK > current )); then qm resize "$VMID" scsi0 "${DISK}G"; fi

if [[ $START == 1 ]]; then
  qm start "$VMID"
  info "waiting for the QEMU guest agent (up to 3 minutes)..."
  for _ in $(seq 1 36); do
    if addr=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | grep -oE '"ip-address" *: *"[0-9.]+"' | grep -v '127.0.0.1' | head -n 1); then
      [[ -n $addr ]] && { ok "${NAME} is up: ${addr##*\"*: \"}" ; break; }
    fi
    sleep 5
  done
fi
ok "VM ${VMID} (${NAME}) deployed: ssh to ${IP%/*} as the template's cloud-init user"
