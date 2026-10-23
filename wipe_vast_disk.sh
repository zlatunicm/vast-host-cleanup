#!/usr/bin/env bash
# Wipe + relabel the former Vast 'vast_client_data' partition (mounted at /var/lib/docker).
# DESTROYS all leftover renter data on that partition. The root filesystem is refused.
# Usage: sudo bash wipe_vast_disk.sh <partition>     e.g. /dev/nvme0n1p3
set -u

if [ $# -ne 1 ] || [ ! -b "$1" ]; then echo "Usage: sudo bash $0 <partition, e.g. /dev/nvme0n1p3>" >&2; exit 1; fi
DEV=$1
DISK=/dev/$(lsblk -no PKNAME "$DEV")
PARTNUM=$(cat "/sys/class/block/$(basename "$DEV")/partition")
NEWLABEL=dockerdata
OLDUUID=$(blkid -s UUID -o value "$DEV")

log(){ echo -e "\n=== $* ==="; }

# Safety: confirm the device is what we expect and NOT the root fs
ROOTSRC=$(findmnt -no SOURCE / 2>/dev/null)
if [ "$ROOTSRC" = "$DEV" ]; then echo "ABORT: $DEV is the root filesystem!"; exit 1; fi
if ! findmnt -no TARGET "$DEV" 2>/dev/null | grep -qx /var/lib/docker; then
  echo "WARN: $DEV is not mounted at /var/lib/docker (it may already be unmounted). Continuing."
fi
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$DEV"
read -r -p "This ERASES everything on $DEV. Type YES to continue: " ok
[ "$ok" = "YES" ] || { echo "Aborted."; exit 1; }

log "1. Stop Docker stack so /var/lib/docker is free"
systemctl stop docker.socket docker.service containerd.service 2>/dev/null
sleep 2

log "2. Unmount /var/lib/docker"
systemctl stop var-lib-docker.mount 2>/dev/null
if mountpoint -q /var/lib/docker; then
  umount /var/lib/docker 2>/dev/null || {
    echo "busy -> killing holders"; fuser -km /var/lib/docker 2>/dev/null; sleep 2
    umount /var/lib/docker 2>/dev/null || umount -l /var/lib/docker
  }
fi
mountpoint -q /var/lib/docker && { echo "ABORT: could not unmount /var/lib/docker"; exit 1; } || echo "unmounted OK"

log "3. Wipe filesystem signatures + reformat XFS (fresh, new UUID, label=$NEWLABEL)"
wipefs -a "$DEV"
mkfs.xfs -f -L "$NEWLABEL" "$DEV"

log "4. Relabel GPT partition name: vast_client_data -> $NEWLABEL"
sgdisk -c ${PARTNUM}:${NEWLABEL} "$DISK" && partprobe "$DISK" 2>/dev/null

log "5. Update /etc/fstab with the new UUID"
NEWUUID=$(blkid -s UUID -o value "$DEV")
echo "new filesystem UUID = $NEWUUID"
cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
# remove any existing /var/lib/docker mount line, then add a clean one (nofail = safe boot)
sed -i '\#[[:space:]]/var/lib/docker/\?[[:space:]]#d' /etc/fstab
echo "UUID=$NEWUUID /var/lib/docker xfs rw,auto,nofail,pquota 0 0" >> /etc/fstab
echo "--- new fstab docker line ---"; grep /var/lib/docker /etc/fstab

log "6. Remount and restart Docker (it reinitialises an empty data root)"
systemctl daemon-reload
mount /var/lib/docker && echo "mounted OK" || { echo "ABORT: mount failed"; exit 1; }
systemctl start containerd.service docker.service docker.socket

log "7. Verify"
echo "-- partition --"; lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$DEV"
echo "-- mount/usage --"; df -h /var/lib/docker
echo "-- docker --"; systemctl is-active docker; docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | head
echo "-- old UUID still referenced anywhere? --"; [ -n "$OLDUUID" ] && grep -R "$OLDUUID" /etc/fstab && echo "WARNING: stale UUID present" || echo "no stale UUID"

log "DONE. Disk wiped, relabelled '$NEWLABEL', Docker running on a clean empty data root."
