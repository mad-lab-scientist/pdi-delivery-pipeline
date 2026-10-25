#!/usr/bin/env bash
# =============================================================================
# pve-cloudinit-template.sh: build a Proxmox VE cloud-init VM template from an official cloud image,
# with the image's checksum verified against the vendor's published checksum file.
#
#   ./pve-cloudinit-template.sh                                    interactive
#   ./pve-cloudinit-template.sh --image ubuntu-24.04 --vmid 9000 --storage local-lvm --bridge vmbr0 \
#       --vlan 30 --ci-user opsadmin --ssh-keys ~/.ssh/authorized_keys --yes
#
# Images: ubuntu-24.04, debian-12, rocky-9. The template gets: virtio-scsi single, discard/SSD
# emulation, QEMU guest agent enabled, serial console, a cloud-init drive and DHCP by default (clones
# set their own static IP; see pve-clone-vm.sh). Run as root on a PVE 8+ node.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../../linux/lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../../linux/lib/common.sh"

IMAGE="" VMID="" STORAGE="" BRIDGE="" VLAN="" CI_USER="" SSH_KEYS="" NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --image) IMAGE=$2; shift 2 ;;
    --vmid) VMID=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --storage) STORAGE=$2; shift 2 ;;
    --bridge) BRIDGE=$2; shift 2 ;;
    --vlan) VLAN=$2; shift 2 ;;
    --ci-user) CI_USER=$2; shift 2 ;;
    --ssh-keys) SSH_KEYS=$2; shift 2 ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '3,13p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
command -v qm >/dev/null || die "run this on a Proxmox VE node"

declare -A URL SUMS ALGO
URL[ubuntu-24.04]=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
SUMS[ubuntu-24.04]=https://cloud-images.ubuntu.com/noble/current/SHA256SUMS; ALGO[ubuntu-24.04]=sha256
URL[debian-12]=https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
SUMS[debian-12]=https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS; ALGO[debian-12]=sha512
URL[rocky-9]=https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
SUMS[rocky-9]=https://dl.rockylinux.org/pub/rocky/9/images/x86_64/CHECKSUM; ALGO[rocky-9]=sha256

is_image() { [[ -n "${URL[$1]:-}" ]]; }
is_free_vmid() { [[ $1 =~ ^[0-9]{3,9}$ ]] && ! qm status "$1" >/dev/null 2>&1 && ! pct status "$1" >/dev/null 2>&1; }
is_storage() { pvesm status --content images 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$1"; }
is_bridge() { [[ -d "/sys/class/net/$1/bridge" ]]; }
is_vlan() { [[ -z $1 || ( $1 =~ ^[0-9]{1,4}$ && $1 -ge 1 && $1 -le 4094 ) ]]; }

info "images: ${!URL[*]}"
ask IMAGE "Cloud image" "ubuntu-24.04" is_image
ask VMID "Template VMID" "9000" is_free_vmid
ask NAME "Template name" "tpl-${IMAGE}" is_hostname
info "storages with 'images' content: $(pvesm status --content images | awk 'NR > 1 {printf "%s ", $1}')"
ask STORAGE "Target storage" "local-lvm" is_storage
ask BRIDGE "Bridge" "vmbr0" is_bridge
if [[ -z $VLAN && $ASSUME_YES == 0 && -t 0 ]]; then read -r -p "VLAN tag (blank for untagged): " VLAN; fi
is_vlan "$VLAN" || die "VLAN must be 1-4094"
ask CI_USER "Cloud-init default user" "opsadmin" is_hostname
if [[ -z $SSH_KEYS && $ASSUME_YES == 0 && -t 0 ]]; then read -r -p "Public key file for that user (blank to skip): " SSH_KEYS; fi
[[ -z $SSH_KEYS || -r $SSH_KEYS ]] || die "cannot read $SSH_KEYS"

step "Download and verify ${IMAGE}"
cache=/var/lib/vz/template/cloud
mkdir -p "$cache"
file="$cache/$(basename "${URL[$IMAGE]}")"
sums=$(curl -fsSL "${SUMS[$IMAGE]}")
base=$(basename "$file")
expected=$(awk -v f="$base" '$2 == f || $2 == "*"f {print $1} $1 ~ /^SHA(256|512)$/ && $2 == "("f")" {print $4}' <<< "$sums" | head -n 1)
[[ -n $expected ]] || die "no checksum for ${base} in ${SUMS[$IMAGE]}"
if [[ ! -f $file ]] || ! echo "${expected}  ${file}" | "${ALGO[$IMAGE]}sum" -c --quiet - 2>/dev/null; then
  curl -fL --progress-bar -o "$file.part" "${URL[$IMAGE]}"
  echo "${expected}  ${file}.part" | "${ALGO[$IMAGE]}sum" -c --quiet - || { rm -f "$file.part"; die "checksum mismatch: download rejected"; }
  mv "$file.part" "$file"
fi
ok "verified ${ALGO[$IMAGE]} ${expected:0:16}..."

step "Create template ${VMID} (${NAME})"
net="virtio,bridge=${BRIDGE},firewall=1${VLAN:+,tag=${VLAN}}"
confirm "Create VM ${VMID} on ${STORAGE} attached to ${BRIDGE}${VLAN:+ VLAN ${VLAN}}?" || die "aborted"
qm create "$VMID" --name "$NAME" --ostype l26 --machine q35 --bios ovmf --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=0" \
  --cpu x86-64-v2-AES --cores 2 --memory 2048 --balloon 1024 --net0 "$net" --scsihw virtio-scsi-single \
  --agent enabled=1,fstrim_cloned_disks=1 --serial0 socket --vga serial0 --description "Cloud-init template from ${URL[$IMAGE]} (${ALGO[$IMAGE]} ${expected:0:16}...)"
qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${file},discard=on,ssd=1,iothread=1"
qm set "$VMID" --ide2 "${STORAGE}:cloudinit" --boot order=scsi0
qm set "$VMID" --ciuser "$CI_USER" --ipconfig0 ip=dhcp --ciupgrade 1
[[ -n $SSH_KEYS ]] && qm set "$VMID" --sshkeys "$SSH_KEYS"
qm template "$VMID"
ok "template ${VMID} ready: clone it with ./pve-clone-vm.sh --template ${VMID}"
