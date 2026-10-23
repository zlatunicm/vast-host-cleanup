#!/usr/bin/env bash
# Force-purge Vast.ai HOST software from this machine.
# WARNING: this terminates any active rental on the machine. Run as root.
set -u

log(){ echo -e "\n=== $* ==="; }

log "1. Stop cron auto-restart (so nothing respawns)"
rm -f /etc/cron.d/vastai_kaalia_update /etc/cron.d/vastai_restart_everything
# kill any in-flight restart scripts
pkill -f vastai_restart 2>/dev/null

log "2. Stop + disable + mask all Vast systemd services"
for u in vastai.service vast_metrics.service vastai_kaalia.service vastai_bouncer.service; do
  systemctl stop "$u"    2>/dev/null && echo "stopped  $u"
  systemctl disable "$u" 2>/dev/null && echo "disabled $u"
  systemctl mask "$u"    2>/dev/null
done

log "3. Kill remaining Vast host processes (kaalia, reverse tunnel, vast sshd)"
pkill -9 -f '/var/lib/vastai_kaalia/' 2>/dev/null
pkill -9 -f 'kaalia'                  2>/dev/null
pkill -9 -f 'ssh.*ssh1.vast.ai'       2>/dev/null
pkill -9 -f 'sshd:.*vastai_kaalia'    2>/dev/null
pkill -9 -f '/etc/forward_key'        2>/dev/null

log "4. Stop + remove ALL Vast renter containers (C.*) and their images"
imgs=""
for cid in $(docker ps -a --filter 'name=C.' --format '{{.ID}}'); do
  img=$(docker inspect -f '{{.Image}}' "$cid" 2>/dev/null)
  echo "removing container $cid (image $img)"
  docker rm -f "$cid" 2>/dev/null
  imgs="$imgs $img"
done
for img in $imgs; do docker rmi -f "$img" 2>/dev/null; done

log "5. Remove Vast systemd unit files + reload"
rm -f /etc/systemd/system/vastai.service \
      /etc/systemd/system/vast_metrics.service \
      /etc/systemd/system/vastai_kaalia.service \
      /etc/systemd/system/vastai_bouncer.service \
      /etc/systemd/system/multi-user.target.wants/vastai.service \
      /etc/systemd/system/multi-user.target.wants/vast_metrics.service
systemctl daemon-reload
systemctl reset-failed 2>/dev/null

log "6. Delete Vast files/dirs"
rm -rf /var/lib/vastai_kaalia
rm -rf /opt/portal-aio /opt/supervisor-scripts
rm -rf /var/log/portal
rm -f  /etc/forward_key
rm -f  /usr/local/bin/log-tee 2>/dev/null

log "7. Remove the vastai_kaalia user"
userdel vastai_kaalia 2>/dev/null && echo "user removed" || echo "user not present / already gone"

log "8. Verify — anything left below is residual"
echo "-- processes --"; ps aux | grep -iE 'vast|kaalia|portal-aio' | grep -v grep
echo "-- services --"; systemctl list-units --all 2>/dev/null | grep -i vast
echo "-- containers --"; docker ps -a --format '{{.Names}} {{.Status}}'
echo "-- dirs --"; ls -d /var/lib/vastai_kaalia /opt/portal-aio 2>/dev/null || echo "vast dirs gone"
echo "-- tunnel --"; ss -tnp 2>/dev/null | grep -i vast.ai || echo "no vast.ai tunnel"

log "DONE. Vast.ai host software purged."
echo "Note: the 'vast_client_data' disk was left mounted and untouched."
echo "To wipe and relabel it as well, see wipe_vast_disk.sh."
