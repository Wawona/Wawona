#!/usr/bin/env bash
# Fail closed unless Colima is installed and the default VM is running.
# Catalog Wayland guests on Darwin must use Colima + waypipe (not local-bundle).
#
# Usage:
#   scripts/appium/ensure-colima.sh
#   WAWONA_COLIMA_START=1 scripts/appium/ensure-colima.sh   # start if stopped
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${HOME}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH:-}"

# Host brew often missing in agent shells; resolve colima from nix if needed.
if ! command -v colima >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1; then
    _colima_out="$(nix build --no-link --print-out-paths 'nixpkgs#colima' 2>/dev/null | head -1 || true)"
    _lima_out="$(nix build --no-link --print-out-paths 'nixpkgs#lima' 2>/dev/null | head -1 || true)"
    if [[ -n "${_colima_out}" && -x "${_colima_out}/bin/colima" ]]; then
      export PATH="${_colima_out}/bin:${_lima_out:+${_lima_out}/bin:}${PATH}"
    fi
  fi
fi

if ! command -v colima >/dev/null 2>&1; then
  echo "FAIL: colima not on PATH. Install via brew (colima lima) or nix profile, then colima start." >&2
  exit 6
fi

if status_out="$(colima status 2>&1)"; then
  echo "colima already running"
else
  if [[ "${WAWONA_COLIMA_START:-0}" == "1" ]]; then
    echo "colima not running; starting (WAWONA_COLIMA_START=1)"
    if [[ -n "${WAWONA_COLIMA_VM_TYPE:-}" ]]; then
      colima start --vm-type "$WAWONA_COLIMA_VM_TYPE"
    else
      colima start
    fi
  else
    echo "FAIL: colima not running. Start with: colima start" >&2
    echo "$status_out" >&2
    exit 6
  fi
fi

COLIMA_HOME="${COLIMA_HOME:-$HOME/.colima}"
SSH_CONFIG="${COLIMA_SSH_CONFIG:-$COLIMA_HOME/ssh_config}"
mkdir -p "$(dirname "$SSH_CONFIG")"
refresh_ssh_config() {
  local ssh_config_tmp
  ssh_config_tmp="$(mktemp "${TMPDIR:-/tmp}/wawona-colima-ssh.XXXXXX")"
  if ! colima ssh-config >"$ssh_config_tmp" || [[ ! -s "$ssh_config_tmp" ]]; then
    rm -f "$ssh_config_tmp"
    return 1
  fi
  mv "$ssh_config_tmp" "$SSH_CONFIG"
}

check_colima_ssh() {
  ssh -F "$SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    colima 'true' >/dev/null 2>&1
}

if ! refresh_ssh_config || ! check_colima_ssh; then
  if [[ "${WAWONA_COLIMA_RECOVER:-0}" != "1" ]]; then
    echo "FAIL: Colima SSH config or guest connection is unhealthy" >&2
    exit 6
  fi

  echo "Colima reports stale guest state; force-stopping and restarting CI VM"
  if ! colima stop --force || ! colima start; then
    echo "FAIL: could not recover Colima CI VM" >&2
    exit 6
  fi

  if ! refresh_ssh_config || ! check_colima_ssh; then
    echo "FAIL: Colima guest remains unreachable after CI VM recovery" >&2
    exit 6
  fi
fi

if [[ ! -s "$SSH_CONFIG" ]]; then
  echo "FAIL: refreshed Colima SSH configuration is empty at $SSH_CONFIG" >&2
  exit 6
fi

echo "colima ok ssh-config=$SSH_CONFIG"
