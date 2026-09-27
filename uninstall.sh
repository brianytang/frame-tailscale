#!/usr/bin/env bash
set -eu -o pipefail

if (( EUID != 0 )); then
  echo "Run this uninstaller as root (sudo bash uninstall.sh)." >&2
  exit 1
fi

if systemctl is-active --quiet tailscaled; then
  systemctl stop tailscaled
fi
if systemctl is-enabled --quiet tailscaled; then
  systemctl disable tailscaled
fi

rm -f /etc/systemd/system/tailscaled.service
rm -f /etc/systemd/system/tailscaled.service.d/override.conf
rm -f /etc/systemd/system/tailscaled.service.d/override.conf.bak
if [ -d /etc/systemd/system/tailscaled.service.d ]; then
  rmdir --ignore-fail-on-non-empty /etc/systemd/system/tailscaled.service.d
fi
rm -f /etc/default/tailscaled
rm -f /etc/profile.d/tailscale.sh
rm -f /etc/atomic-update.conf.d/tailscale.conf
rm -rf /home/steamos/tailscale

systemctl daemon-reload

# Preserve /var/lib/tailscale so reinstalling retains the device's identity.
echo "Uninstallation complete. Tailscale state has been preserved for reinstalling."
