#!/usr/bin/env bash
# Sourced by install/uninstall before any privileged service cleanup.
install_dir=${install_dir:?Missing installation directory}

check_installation_paths() {
  local path owner mode
  for path in / /home "$install_dir" "$install_dir/tailscale" "$install_dir/tailscaled"; do
    if [[ -L "$path" ]]; then
      echo "Refusing symlinked installation path: $path" >&2
      exit 1
    fi
    if [[ ! -e "$path" && "$path" == "$install_dir"* ]]; then continue; fi
    if [[ "$path" == "$install_dir/tailscale" || "$path" == "$install_dir/tailscaled" ]]; then
      [[ -f "$path" ]] || { echo "Expected a regular executable file: $path" >&2; exit 1; }
    else
      [[ -d "$path" ]] || { echo "Expected a real directory: $path" >&2; exit 1; }
    fi
    owner=$(stat -c %u -- "$path")
    mode=$(stat -c %a -- "$path")
    if [[ "$owner" != 0 ]] || (( (8#$mode & 0022) != 0 )); then
      echo "Installation path must be root-owned and not group/other writable: $path" >&2
      exit 1
    fi
  done
}

check_service_paths() {
  local commands
  commands=$(systemctl show tailscaled --value \
    --property=ExecCondition --property=ExecStartPre --property=ExecStart \
    --property=ExecStartPost --property=ExecStop --property=ExecStopPost)
  if [[ "$commands" == *'/home/steamos/tailscale'* ]]; then
    echo 'Refusing the legacy user-controlled service path. Secure or remove its unit before migrating; see readme.md.' >&2
    exit 1
  fi
}
