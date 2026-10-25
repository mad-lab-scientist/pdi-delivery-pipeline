#!/usr/bin/env bash
# =============================================================================
# lvm-extend.sh: grow a logical volume and its filesystem after the underlying disk was enlarged
# (hypervisor or cloud disk resize), in one safe pass: rescan, grow the partition, pvresize,
# lvextend --resizefs. Works for ext4 and XFS on SCSI, virtio and NVMe disks.
#
#   sudo ./lvm-extend.sh                                    interactive: pick the LV, default +100%FREE
#   sudo ./lvm-extend.sh --lv /dev/ubuntu-vg/ubuntu-lv --size +20G --yes
#   sudo ./lvm-extend.sh --lv rhel/root --dry-run
# Requires: lvm2, and growpart (cloud-guest-utils on Debian/Ubuntu, cloud-utils-growpart on RHEL/SUSE)
# when the physical volume is a partition.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

LV="" SIZE="+100%FREE"
while [[ $# -gt 0 ]]; do
  case $1 in
    --lv) LV=$2; shift 2 ;;
    --size) SIZE=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
require_root
command -v lvs >/dev/null || die "lvm2 is not installed"

step "Logical volumes"
lvs --noheadings -o lv_path,lv_size,vg_name,vg_free --units g 2>/dev/null | awk '{printf "  %-36s %10s  (VG %s, %s free)\n", $1, $2, $3, $4}'
is_lv() { lvs "$1" >/dev/null 2>&1; }
ask LV "Logical volume to extend (path or vg/lv)" "$(findmnt -no SOURCE / 2>/dev/null)" is_lv
[[ $SIZE =~ ^\+([0-9]+(\.[0-9]+)?[KMGTkmgt]|[0-9]{1,3}%(FREE|VG|PVS))$ ]] || die "size must look like +20G or +100%FREE"
VG=$(lvs --noheadings -o vg_name "$LV" | tr -d ' ')
MOUNT=$(findmnt -no TARGET "$(lvs --noheadings -o lv_dm_path "$LV" | tr -d ' ')" 2>/dev/null | head -n 1 || true)
info "VG ${VG}; mounted on ${MOUNT:-(not mounted)}"
[[ -n "$MOUNT" ]] && df -h "$MOUNT" | sed 's/^/  /'

step "Growing physical volumes of ${VG}"
mapfile -t PVS < <(pvs --noheadings -o pv_name -S "vg_name=${VG}" | tr -d ' ')
for pv in "${PVS[@]}"; do
  dev=$(basename "$(readlink -f "$pv")")
  if [[ -f "/sys/class/block/${dev}/partition" ]]; then
    disk=$(lsblk -no PKNAME "/dev/${dev}" | head -n 1)
    part=$(cat "/sys/class/block/${dev}/partition")
    [[ -w "/sys/class/block/${disk}/device/rescan" ]] && run sh -c "echo 1 > /sys/class/block/${disk}/device/rescan"
    command -v growpart >/dev/null || die "growpart is needed to grow ${pv} (install cloud-guest-utils / cloud-utils-growpart)"
    # growpart exits 1 with NOCHANGE when the partition already fills the disk.
    out=$(run growpart "/dev/${disk}" "$part" 2>&1) || [[ $out == *NOCHANGE* ]] || die "growpart failed: $out"
    info "${pv}: ${out:-partition grown}"
  elif [[ -w "/sys/class/block/${dev}/device/rescan" ]]; then
    run sh -c "echo 1 > /sys/class/block/${dev}/device/rescan"   # whole-disk PV
  fi
  run pvresize "$pv"
done
vgs --noheadings -o vg_name,vg_size,vg_free --units g "$VG" | awk '{printf "  VG %s: %s, %s free\n", $1, $2, $3}'

step "Extending ${LV} by ${SIZE}"
confirm "Extend ${LV} by ${SIZE} and resize its filesystem online?" || die "aborted"
flag=$([[ $SIZE == *%* ]] && echo -l || echo -L)
if ! run lvextend --resizefs "$flag" "$SIZE" "$LV"; then
  warn "lvextend reported an error (often 'matches existing size' when there is no free space)"
fi
[[ -n "$MOUNT" && $DRY_RUN == 0 ]] && df -h "$MOUNT" | sed 's/^/  /'
ok "done"
