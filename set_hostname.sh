#!/usr/bin/env bash
# Rename this machine (updates hostname + /etc/hosts). Run as root.
# Usage: sudo bash set_hostname.sh <new-hostname>
set -eu
if [ $# -ne 1 ]; then echo "Usage: sudo bash $0 <new-hostname>" >&2; exit 1; fi
OLD=$(hostname)
NEW=$1

echo "Renaming '$OLD' -> '$NEW'"

# 1. Set the hostname (persists to /etc/hostname, applies live)
hostnamectl set-hostname "$NEW"

# 2. Fix the 127.0.1.1 line in /etc/hosts so sudo/name resolution stays happy
cp /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
if grep -qE "^127\.0\.1\.1[[:space:]]" /etc/hosts; then
  sed -i -E "s/^(127\.0\.1\.1[[:space:]]+).*/\1$NEW/" /etc/hosts
else
  printf "127.0.1.1\t%s\n" "$NEW" >> /etc/hosts
fi

echo
echo "=== verify ==="
echo "hostname now : $(hostname)"
echo "/etc/hostname: $(cat /etc/hostname)"
echo "/etc/hosts   : $(grep '127.0.1.1' /etc/hosts)"
echo
echo "Done. The new name fully applies in new terminals (and survives reboot)."
