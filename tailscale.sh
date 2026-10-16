#!/usr/bin/env bash

# set invocation settings for this script:
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: the return value of a pipeline is the status of the last command to exit with a non-zero status, or zero if no command exited with a non-zero status
set -eu -o pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_dir=/home/.tailscale-bin

if (( EUID != 0 )); then
  echo "Run this installer as root (sudo bash tailscale.sh)." >&2
  exit 1
fi

# shellcheck source=security.sh
source "$script_dir/security.sh"
check_installation_paths
check_service_paths

case "$(uname -m)" in
  aarch64|arm64) arch=arm64 ;;
  x86_64|amd64) arch=amd64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# make a temporary directory, save the name, and move into it
dir="$(mktemp -d)"
trap 'rm -rf -- "$dir"' EXIT
cd "${dir}"

echo -n "Getting version..."

# get info for the latest version of Tailscale
tarball="$(curl -fsSL 'https://pkgs.tailscale.com/stable/?mode=json' | jq -er --arg arch "$arch" '.Tarballs[$arch]')"
version="$(echo "$tarball" | cut -d_ -f2)"

echo "got ${version}."

echo "Downloading:"

# download the Tailscale package itself
wget -q --show-progress -O tailscale.tgz "https://pkgs.tailscale.com/stable/${tarball}"

echo -n "Removing Legacy Installations..."

# Stop and disable the systemd service
if systemctl is-active --quiet tailscaled; then
  systemctl stop tailscaled
fi
if systemctl is-enabled --quiet tailscaled; then
  systemctl disable tailscaled
fi

# Remove the systemd system extension
if [ $(systemd-sysext list 2>/dev/null | grep -c "/var/lib/extensions/tailscale") -ne 0 ]; then
  systemd-sysext unmerge
  rm -rf /var/lib/extensions/tailscale
  systemd-sysext merge
fi

echo "done."

echo -n "Installing..."

# extract the tailscale binaries
tar xzf tailscale.tgz
tar_dir="${tarball%.tgz}"
test -d "$tar_dir"

# Create binaries directory in home
install -d -o root -g root -m 0755 "$install_dir"

# pull binaries
install -m 0755 "$tar_dir/tailscale" "$install_dir/tailscale"
install -m 0755 "$tar_dir/tailscaled" "$install_dir/tailscaled"

# add binaries to path via profile.d
echo 'export PATH="$PATH:/home/.tailscale-bin"' > /etc/profile.d/tailscale.sh
source /etc/profile.d/tailscale.sh

# copy the systemd file into place
cp -f "$tar_dir/systemd/tailscaled.service" /etc/systemd/system/tailscaled.service

# copy in the defaults file if it doesn't already exist
if ! test -f /etc/default/tailscaled; then
  cp -f "$tar_dir/systemd/tailscaled.defaults" /etc/default/tailscaled
fi

# add atomic-update.conf.d configuration
mkdir -p /etc/atomic-update.conf.d
cat <<EOF > /etc/atomic-update.conf.d/tailscale.conf
/etc/default/tailscaled
/etc/profile.d/tailscale.sh
EOF

# if an override file already exists, back up and remove
if test -f /etc/systemd/system/tailscaled.service.d/override.conf; then
  echo
  echo
  echo "Warning: An existing Tailscaled systemd override file was detected. It must be replaced."
  echo "A backup of the existing file is being placed at /etc/systemd/system/tailscaled.service.d/override.conf.bak"
  echo
  cp -f /etc/systemd/system/tailscaled.service.d/override.conf /etc/systemd/system/tailscaled.service.d/override.conf.bak
  rm /etc/systemd/system/tailscaled.service.d/override.conf
fi

# copy our override file in
mkdir -p /etc/systemd/system/tailscaled.service.d
cp -f "$script_dir/override.conf" /etc/systemd/system/tailscaled.service.d/override.conf

# capture the above override file in systemd
systemctl daemon-reload

echo "done."

echo -n "Starting required services..."

# tailscaled - the tailscale daemon
# Note: enable and start/restart must be run because the legacy installation stops and disables
# any existing installations.
systemctl enable tailscaled
if systemctl is-active --quiet tailscaled; then
  echo "Upgrade complete."
  echo -n "Restarting tailscaled..."
else
  echo "Install complete."
  echo -n "Starting tailscaled..."
fi

# This needs to be the last thing we do in case the user's running this over Tailscale SSH.
systemctl restart tailscaled
systemctl is-active --quiet tailscaled

echo "done."

if ! command -v tailscale &> /dev/null; then
  echo
  echo "Tailscale is installed and running but the binaries are not in your path yet."
  echo "Restart your session or run the following command to add them:"
  echo
  echo "source /etc/profile.d/tailscale.sh"
  echo
fi

echo "Installation Complete."
