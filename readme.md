# Tailscale on Steam Frame

Install Tailscale on Steam Frame without writing to its read-only `/opt`
filesystem. The CLI and daemon live in `/home/steamos/tailscale`, and systemd
runs the daemon and enables it at boot.

The installer downloads the latest stable ARM64 build for Steam Frame. It also
recognizes x86-64, but the installation paths and instructions target the
Frame's `steamos` account.

## Install and connect

Run these commands in a terminal on the Frame, or over its existing local SSH
connection (`ssh steamos@frame.local`). You need internet access, sudo access,
and `git`, `bash`, `curl`, `jq`, `wget`, `tar`, and systemd.

```sh
git clone https://github.com/sherbondy/frame-tailscale.git ~/frame-tailscale
cd ~/frame-tailscale
sudo bash tailscale.sh
source /etc/profile.d/tailscale.sh
sudo /home/steamos/tailscale/tailscale up --operator=steamos
```

Open the printed login URL in a browser and sign in to the same tailnet as your
other devices. You can open it on the Frame or another device. Installation
alone does not sign the Frame in to Tailscale.

The `--operator=steamos` option lets your normal account manage Tailscale after
this initial setup. New login shells load the PATH configuration automatically;
`source` above makes it available in the current shell. Use the full binary path
with `sudo`, which may use a separate PATH.

## Verify the connection

```sh
systemctl is-active tailscaled
systemctl is-enabled tailscaled
tailscale status
tailscale ip -4
```

The service should report `active` and `enabled`. Check that the Frame appears
online in the Tailscale app on another device signed in to the same tailnet.
To test connectivity from the Frame, replace the placeholder with another
online device's Tailscale name or IP:

```sh
tailscale ping <peer-name-or-tailscale-ip>
```

For service logs and health diagnostics:

```sh
journalctl -u tailscaled -n 50 --no-pager
tailscale status --json | jq '{BackendState, Health}'
```

Once connected, expect `BackendState` to be `Running` with no health warnings.

### Optional: Tailscale SSH

Tailscale SSH is not required for tailnet connectivity or for using an existing
OpenSSH server over the Frame's Tailscale IP. To enable Tailscale SSH explicitly:

```sh
tailscale set --ssh
```

Access is subject to your tailnet's SSH policy. Keep a local terminal or local
network SSH connection available when updating or uninstalling Tailscale,
because those operations stop its daemon.

## Update

Run the installer again to download the latest stable binaries and refresh the
service configuration:

```sh
cd ~/frame-tailscale
git pull --ff-only
sudo bash tailscale.sh
```

Run this from a terminal on the Frame or over local network SSH. An SSH session
using Tailscale can disconnect when the installer stops the service.

The installer preserves `/etc/default/tailscaled` and the device's login state.
It replaces the supplied systemd override, backing up an existing override as
`override.conf.bak`. Keep custom service changes in a separate drop-in file.

## Uninstall

```sh
cd ~/frame-tailscale
sudo bash uninstall.sh
```

This stops and disables the daemon and removes both binaries, the systemd unit,
the supplied override and its backup, the PATH configuration, the defaults file,
and the atomic-update configuration. Other systemd drop-ins are left alone.

State in `/var/lib/tailscale` is deliberately preserved, so reinstalling can
reconnect with the same device identity without another login. Uninstalling does
not remove the device entry from your Tailscale account.

## Steam Frame configuration

| Component | Location |
| --- | --- |
| CLI and daemon | `/home/steamos/tailscale/tailscale`, `/home/steamos/tailscale/tailscaled` |
| PATH configuration | `/etc/profile.d/tailscale.sh` |
| Systemd service | `/etc/systemd/system/tailscaled.service` |
| Systemd override | `/etc/systemd/system/tailscaled.service.d/override.conf` |
| Daemon defaults (`PORT`, `FLAGS`) | `/etc/default/tailscaled` |
| Persistent device state | `/var/lib/tailscale` |
| SteamOS atomic-update configuration | `/etc/atomic-update.conf.d/tailscale.conf` |

The override points all daemon commands at the home-directory binaries and
requires that filesystem to be mounted before the service starts. It also sets
`TS_DEBUG_FIREWALL_MODE=nftables`: on the tested Frame, the legacy iptables
backend failed to initialize its filter table after login. Explicitly selecting
nftables resolves that health warning while keeping firewall management enabled.
See [Tailscale's firewall mode documentation](https://tailscale.com/docs/features/firewall-mode).
Tailscale currently documents this environment variable as temporary and subject
to change.

The atomic-update configuration lists the defaults and PATH files for SteamOS
updates. Survival across a SteamOS upgrade has not been verified.

## Troubleshooting

- **`tailscale: command not found`:** run `source /etc/profile.d/tailscale.sh`,
  open a new login shell, or use `/home/steamos/tailscale/tailscale` directly.
- **`NeedsLogin`:** run the initial `tailscale up` command above and finish the
  browser login.
- **Legacy iptables/filter-table errors:** rerun the updated installer and check
  that `systemctl cat tailscaled` includes `TS_DEBUG_FIREWALL_MODE=nftables`.
- **`invalid value "" for flag -port`:** check that `/etc/default/tailscaled`
  contains a valid `PORT`, such as `PORT="41641"`. The installer preserves this
  file when it already exists.

## Validation

Tested on a Steam Frame with Tailscale 1.102.4: installation, uninstallation,
reinstallation, service enablement, browser login, tailnet connectivity, and
visibility in the macOS Tailscale app. Reboot and SteamOS upgrade behavior have
not been tested.

Adapted from [deck-tailscale](https://github.com/tailscale-dev/deck-tailscale)
and the [original Steam Deck guide](https://tailscale.com/blog/steam-deck).
